// 
// Wire
// Copyright (C) 2016 Wire Swiss GmbH
// 
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
// 
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
// 
// You should have received a copy of the GNU General Public License
// along with this program. If not, see http://www.gnu.org/licenses/.
// 


@import ZMTransport;
@import zmessaging;

#import "MessagingTest.h"
#import "ZMLoginCodeRequestTranscoder.h"
#import "ZMAuthenticationStatus.h"
#import "ZMCredentials.h"
#import "ZMAuthenticationStatus.h"
#import "ZMUserSessionAuthenticationNotification.h"

@interface ZMLoginCodeRequestTranscoderTests : MessagingTest

@property (nonatomic) ZMLoginCodeRequestTranscoder *sut;
@property (nonatomic) ZMAuthenticationStatus *authenticationStatus;

@end

@implementation ZMLoginCodeRequestTranscoderTests

- (void)setUp {
    [super setUp];

    self.authenticationStatus = [[ZMAuthenticationStatus alloc]initWithManagedObjectContext:self.uiMOC cookie:nil];
    self.sut = [[ZMLoginCodeRequestTranscoder alloc] initWithManagedObjectContext:self.uiMOC authenticationStatus:self.authenticationStatus];
}

- (void)tearDown {
    self.authenticationStatus = nil;
    [self.sut tearDown];
    self.sut = nil;
    [super tearDown];
}

- (void)testThatItReturnsNoRequestWhenThereAreNoCredentials
{
    ZMTransportRequest *request;
    request = [self.sut.requestGenerators nextRequest];
    XCTAssertNil(request);
}

- (void)testThatItReturnsExpectedRequestWhenThereIsPhoneNumber
{
    NSString *phoneNumber = @"+7123456789";
    [self.authenticationStatus prepareForRequestingPhoneVerificationCodeForLogin:phoneNumber];

    ZMTransportRequest *expectedRequest = [[ZMTransportRequest alloc] initWithPath:@"/login/send" method:ZMMethodPOST payload:@{@"phone": phoneNumber} authentication:ZMTransportRequestAuthNone];
    
    ZMTransportRequest *request;
    ZM_ALLOW_MISSING_SELECTOR(request = [self.sut.requestGenerators firstNonNilReturnedFromSelector:@selector(nextRequest)]);
    XCTAssertEqualObjects(request, expectedRequest);
}

- (void)testThatItInformTheAuthCenterThatTheCodeWasReceived
{
    // given
    NSString *phoneNumber = @"+7123456789";
    [self.authenticationStatus prepareForRequestingPhoneVerificationCodeForLogin:phoneNumber];
    ZMTransportRequest *request = [self.sut.requestGenerators nextRequest];
    
    // when
    [request completeWithResponse:[ZMTransportResponse responseWithPayload:nil HTTPStatus:200 transportSessionError:nil]];
    WaitForAllGroupsToBeEmpty(0.2);
    
    // then
    XCTAssertEqual(self.authenticationStatus.currentPhase, ZMAuthenticationPhaseUnauthenticated);
}

- (void)testThatItInformTheAuthCenterThatTheCodeRequestFailed
{
    // given
    NSString *phoneNumber = @"+7123456789";
    [self.authenticationStatus prepareForRequestingPhoneVerificationCodeForLogin:phoneNumber];
    ZMTransportRequest *request = [self.sut.requestGenerators nextRequest];
 
    // expect
    XCTestExpectation *expectation = [self expectationWithDescription:@"user session authentication notification"];
    id token = [ZMUserSessionAuthenticationNotification addObserverWithBlock:^(ZMUserSessionAuthenticationNotification *note) {
        XCTAssertEqual(note.error.code, (long) ZMUserSessionUnkownError);
        XCTAssertEqualObjects(note.error.domain, ZMUserSessionErrorDomain);
        [expectation fulfill];
    }];
    
    // when
    [request completeWithResponse:[ZMTransportResponse responseWithPayload:nil HTTPStatus:400 transportSessionError:nil]];
    WaitForAllGroupsToBeEmpty(0.2);
    
    // then
    XCTAssertEqual(self.authenticationStatus.currentPhase, ZMAuthenticationPhaseUnauthenticated);
    XCTAssertTrue([self waitForCustomExpectationsWithTimeout:0.5]);
    
    [ZMUserSessionAuthenticationNotification removeObserver:token];
}


- (void)testThatItInformTheAuthCenterThatTheCodeRequestFailedBecauseOfInvalidPhoneNumber
{
    // given
    NSString *phoneNumber = @"+7123456789";
    [self.authenticationStatus prepareForRequestingPhoneVerificationCodeForLogin:phoneNumber];
    ZMTransportRequest *request = [self.sut.requestGenerators nextRequest];
    
    // expect
    XCTestExpectation *expectation = [self expectationWithDescription:@"user session authentication notification"];
    id token = [ZMUserSessionAuthenticationNotification addObserverWithBlock:^(ZMUserSessionAuthenticationNotification *note) {
        XCTAssertEqual(note.error.code, (long) ZMUserSessionInvalidPhoneNumber);
        XCTAssertEqualObjects(note.error.domain, ZMUserSessionErrorDomain);
        [expectation fulfill];
    }];
    
    // when
    [request completeWithResponse:[ZMTransportResponse responseWithPayload:@{@"label":@"invalid-phone"} HTTPStatus:400 transportSessionError:nil]];
    WaitForAllGroupsToBeEmpty(0.2);
    
    // then
    XCTAssertEqual(self.authenticationStatus.currentPhase, ZMAuthenticationPhaseUnauthenticated);
    XCTAssertTrue([self waitForCustomExpectationsWithTimeout:0.5]);
    
    [ZMUserSessionAuthenticationNotification removeObserver:token];
}


- (void)testThatItInformTheAuthCenterThatTheCodeRequestFailedBecauseOfPendingLogin
{
    // given
    NSString *phoneNumber = @"+7123456789";
    [self.authenticationStatus prepareForRequestingPhoneVerificationCodeForLogin:phoneNumber];
    ZMTransportRequest *request = [self.sut.requestGenerators nextRequest];
    
    // expect
    XCTestExpectation *expectation = [self expectationWithDescription:@"user session authentication notification"];
    id token = [ZMUserSessionAuthenticationNotification addObserverWithBlock:^(ZMUserSessionAuthenticationNotification *note) {
        XCTAssertEqual(note.error.code, (long) ZMUserSessionCodeRequestIsAlreadyPending);
        XCTAssertEqualObjects(note.error.domain, ZMUserSessionErrorDomain);
        [expectation fulfill];
    }];
    
    // when
    [request completeWithResponse:[ZMTransportResponse responseWithPayload:@{@"label":@"pending-login"} HTTPStatus:403 transportSessionError:nil]];
    WaitForAllGroupsToBeEmpty(0.2);
    
    // then
    XCTAssertEqual(self.authenticationStatus.currentPhase, ZMAuthenticationPhaseUnauthenticated);
    XCTAssertTrue([self waitForCustomExpectationsWithTimeout:0.5]);
    
    [ZMUserSessionAuthenticationNotification removeObserver:token];
}


- (void)testThatItInformTheAuthCenterThatTheCodeRequestFailedBecauseThePhoneIsUnauthorized
{
    // given
    NSString *phoneNumber = @"+7123456789";
    [self.authenticationStatus prepareForRequestingPhoneVerificationCodeForLogin:phoneNumber];
    ZMTransportRequest *request = [self.sut.requestGenerators nextRequest];
    
    // expect
    XCTestExpectation *expectation = [self expectationWithDescription:@"user session authentication notification"];
    id token = [ZMUserSessionAuthenticationNotification addObserverWithBlock:^(ZMUserSessionAuthenticationNotification *note) {
        XCTAssertEqual(note.error.code, (long) ZMUserSessionInvalidPhoneNumber);
        XCTAssertEqualObjects(note.error.domain, ZMUserSessionErrorDomain);
        [expectation fulfill];
    }];
    
    // when
    [request completeWithResponse:[ZMTransportResponse responseWithPayload:@{@"label":@"unauthorized"} HTTPStatus:403 transportSessionError:nil]];
    WaitForAllGroupsToBeEmpty(0.2);
    
    // then
    XCTAssertEqual(self.authenticationStatus.currentPhase, ZMAuthenticationPhaseUnauthenticated);
    XCTAssertTrue([self waitForCustomExpectationsWithTimeout:0.5]);
    
    [ZMUserSessionAuthenticationNotification removeObserver:token];
}

@end
