#import "XMLRPCConnection.h"
#import "XMLRPCConnectionManager.h"
#import "XMLRPCRequest.h"
#import "XMLRPCResponse.h"
#import "NSStringAdditions.h"

static NSOperationQueue *parsingQueue;

@interface XMLRPCConnection (XMLRPCConnectionPrivate)

- (void)connection: (NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response;

- (void)connection: (NSURLConnection *)connection didReceiveData: (NSData *)data;

- (void)connection: (NSURLConnection *)connection didSendBodyData: (NSInteger)bytesWritten totalBytesWritten: (NSInteger)totalBytesWritten totalBytesExpectedToWrite: (NSInteger)totalBytesExpectedToWrite;

- (void)connection: (NSURLConnection *)connection didFailWithError: (NSError *)error;

#pragma mark -

- (BOOL)connection: (NSURLConnection *)connection canAuthenticateAgainstProtectionSpace: (NSURLProtectionSpace *)protectionSpace;

- (void)connection: (NSURLConnection *)connection didReceiveAuthenticationChallenge: (NSURLAuthenticationChallenge *)challenge;

- (void)connection: (NSURLConnection *)connection didCancelAuthenticationChallenge: (NSURLAuthenticationChallenge *)challenge;

- (void)connectionDidFinishLoading: (NSURLConnection *)connection;

#pragma mark -

- (void)requestTimedOut;

- (void)invalidateTimeout;

#pragma mark -

+ (NSOperationQueue *)parsingQueue;

@end

#pragma mark -

@implementation XMLRPCConnection

- (id)initWithXMLRPCRequest: (XMLRPCRequest *)request delegate: (id<XMLRPCConnectionDelegate>)delegate manager: (XMLRPCConnectionManager *)manager {
    self = [super init];
    if (self) {
#if ! __has_feature(objc_arc)
        myManager = [manager retain];
        myRequest = [request retain];
        myIdentifier = [[NSString stringByGeneratingUUID] retain];
#else
        myManager = manager;
        myRequest = request;
        myIdentifier = [NSString stringByGeneratingUUID];
#endif
        myData = [[NSMutableData alloc] init];
        
        myConnection = [[NSURLConnection alloc] initWithRequest: [request request] delegate: self];
        
#if ! __has_feature(objc_arc)
        myDelegate = [delegate retain];
#else
        myDelegate = delegate;
#endif
        
        if (myConnection) {
//            DLog(@"The connection, %@, has been established!", myIdentifier);

            [self performSelector: @selector(requestTimedOut) withObject: nil afterDelay: [myRequest timeoutInterval]];
        } else {
            NSLog(@"The connection, %@, could not be established!", myIdentifier);
#if ! __has_feature(objc_arc)
            [self release];
#endif
            return nil;
        }
    }
    
    return self;
}

#pragma mark -

+ (XMLRPCResponse *)sendSynchronousXMLRPCRequest: (XMLRPCRequest *)request error: (NSError **)error {
    NSHTTPURLResponse *response = nil;
#if ! __has_feature(objc_arc)
    NSData *data = [[[NSURLConnection sendSynchronousRequest: [request request] returningResponse: &response error: error] retain] autorelease];
#else
    NSData *data = [NSURLConnection sendSynchronousRequest: [request request] returningResponse: &response error: error];
#endif
    
    if (response) {
        NSInteger statusCode = [response statusCode];
        
        if ((statusCode < 400) && data) {
#if ! __has_feature(objc_arc)
            return [[[XMLRPCResponse alloc] initWithData: data] autorelease];
#else
            return [[XMLRPCResponse alloc] initWithData: data];
#endif
        }
    }
    
    return nil;
}

#pragma mark -

- (NSString *)identifier {
#if ! __has_feature(objc_arc)
    return [[myIdentifier retain] autorelease];
#else
    return myIdentifier;
#endif
}

#pragma mark -

- (id<XMLRPCConnectionDelegate>)delegate {
    return myDelegate;
}

#pragma mark -

- (void)cancel {
    [myConnection cancel];

    [self invalidateTimeout];
}

#pragma mark -

- (void)dealloc {    
#if ! __has_feature(objc_arc)
    [myManager release];
    [myRequest release];
    [myIdentifier release];
    [myData release];
    [myConnection release];
    [myDelegate release];
    
    [super dealloc];
#endif
}

@end

#pragma mark -

@implementation XMLRPCConnection (XMLRPCConnectionPrivate)

- (void)connection: (NSURLConnection *)connection didReceiveResponse: (NSURLResponse *)response {
    if([response respondsToSelector: @selector(statusCode)]) {
        NSInteger statusCode = [(NSHTTPURLResponse *)response statusCode];
        
        if(statusCode >= 400) {
            NSError *error = [NSError errorWithDomain: @"HTTP" code: statusCode userInfo: nil];
            
            [myDelegate request: myRequest didFailWithError: error];
        } else if (statusCode == 304) {
            [myManager closeConnectionForIdentifier: myIdentifier];
        }
    }
    
    [myData setLength: 0];
}

- (void)connection: (NSURLConnection *)connection didReceiveData: (NSData *)data {
    [myData appendData: data];
}

- (void)connection: (NSURLConnection *)connection didSendBodyData: (NSInteger)bytesWritten totalBytesWritten: (NSInteger)totalBytesWritten totalBytesExpectedToWrite: (NSInteger)totalBytesExpectedToWrite {
    if ([myDelegate respondsToSelector: @selector(request:didSendBodyData:)]) {
        float percent = totalBytesWritten / (float)totalBytesExpectedToWrite;
        
        [myDelegate request:myRequest didSendBodyData:percent];
    }
}

- (void)connection: (NSURLConnection *)connection didFailWithError: (NSError *)error {
#if ! __has_feature(objc_arc)
    XMLRPCRequest *request = [[myRequest retain] autorelease];
#else
    XMLRPCRequest *request = myRequest;
#endif

    NSLog(@"The connection, %@, failed with the following error: %@", myIdentifier, [error localizedDescription]);

    [self invalidateTimeout];

    [myDelegate request: request didFailWithError: error];
    
    [myManager closeConnectionForIdentifier: myIdentifier];
}

#pragma mark -

- (BOOL)connection: (NSURLConnection *)connection canAuthenticateAgainstProtectionSpace: (NSURLProtectionSpace *)protectionSpace {
    return [myDelegate request: myRequest canAuthenticateAgainstProtectionSpace: protectionSpace];
}

- (void)connection: (NSURLConnection *)connection didReceiveAuthenticationChallenge: (NSURLAuthenticationChallenge *)challenge {
    [myDelegate request: myRequest didReceiveAuthenticationChallenge: challenge];
}

- (void)connection: (NSURLConnection *)connection didCancelAuthenticationChallenge: (NSURLAuthenticationChallenge *)challenge {
    [myDelegate request: myRequest didCancelAuthenticationChallenge: challenge];
}

- (void)connectionDidFinishLoading: (NSURLConnection *)connection {
    [self invalidateTimeout];
    
    if (myData && ([myData length] > 0)) {
        NSBlockOperation *parsingOperation;

#if ! __has_feature(objc_arc)
        parsingOperation = [NSBlockOperation blockOperationWithBlock:^{
            XMLRPCResponse *response = [[[XMLRPCResponse alloc] initWithData: myData] autorelease];
            XMLRPCRequest *request = [[myRequest retain] autorelease];

            [[NSOperationQueue mainQueue] addOperation: [NSBlockOperation blockOperationWithBlock:^{
               [myDelegate request: request didReceiveResponse: response]; 
            }]];
        }];
#else
        parsingOperation = [NSBlockOperation blockOperationWithBlock:^{
            XMLRPCResponse *response = [[XMLRPCResponse alloc] initWithData: myData];
            XMLRPCRequest *request = myRequest;

            [[NSOperationQueue mainQueue] addOperation: [NSBlockOperation blockOperationWithBlock:^{
                [myDelegate request: request didReceiveResponse: response];

                [myManager closeConnectionForIdentifier:myIdentifier];
            }]];
        }];
#endif
        
        [[XMLRPCConnection parsingQueue] addOperation: parsingOperation];
    }
    else {
        [myManager closeConnectionForIdentifier:myIdentifier];
    }
}

#pragma mark -
- (void)requestTimedOut {
    NSURL *requestURL = [myRequest URL];
    NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys: requestURL, NSURLErrorFailingURLErrorKey, [requestURL absoluteString], NSURLErrorFailingURLStringErrorKey,
        @"The request timed out.", NSLocalizedDescriptionKey, nil];

    [self connection: myConnection didFailWithError: [NSError errorWithDomain: NSURLErrorDomain code: NSURLErrorTimedOut userInfo: userInfo]];
}

- (void)invalidateTimeout {
    [NSObject cancelPreviousPerformRequestsWithTarget: self selector: @selector(requestTimedOut) object:nil];
}

#pragma mark -

+ (NSOperationQueue *)parsingQueue {
    if (parsingQueue == nil) {
        parsingQueue = [[NSOperationQueue alloc] init];
    }
    
    return parsingQueue;
}

@end
