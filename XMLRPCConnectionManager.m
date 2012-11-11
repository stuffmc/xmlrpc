#import "XMLRPCConnectionManager.h"
#import "XMLRPCConnection.h"
#import "XMLRPCRequest.h"

@implementation XMLRPCConnectionManager

static XMLRPCConnectionManager *sharedInstance = nil;

- (id)init {
    self = [super init];
    if (self) {
        myConnections = [[NSMutableDictionary alloc] init];
    }
    
    return self;
}

#pragma mark -

+ (id)allocWithZone: (NSZone *)zone {
    @synchronized(self) {
        if (!sharedInstance) {
            sharedInstance = [super allocWithZone: zone];
            
            return sharedInstance;
        }
    }
    
    return nil;
}

#pragma mark -

+ (XMLRPCConnectionManager *)sharedManager {
    @synchronized(self) {
        if (!sharedInstance) {
            sharedInstance = [[self alloc] init];
        }
    }
    
    return sharedInstance;
}

#pragma mark -

+ (void)spawn:(NSString*)stringURL method:(NSString*)method params:(NSArray*)params delegate: (id<XMLRPCConnectionDelegate>)delegate
{
    DLog(@"%@ sent to %@", method, stringURL);
    NSURL *URL = [NSURL URLWithString:stringURL];
    XMLRPCRequest *request = [[[XMLRPCRequest alloc] initWithURL:URL] autorelease];
    XMLRPCConnectionManager *manager = [XMLRPCConnectionManager sharedManager];
    [request setMethod:method withParameter:params];
    [manager spawnConnectionWithXMLRPCRequest:request delegate:delegate];
}

- (NSString *)spawnConnectionWithXMLRPCRequest: (XMLRPCRequest *)request delegate: (id<XMLRPCConnectionDelegate>)delegate {
    XMLRPCConnection *newConnection = [[XMLRPCConnection alloc] initWithXMLRPCRequest: request delegate: delegate manager: self];
#if ! __has_feature(objc_arc)
    NSString *identifier = [[[newConnection identifier] retain] autorelease];
#else
    NSString *identifier = [newConnection identifier];
#endif
    
    [myConnections setObject: newConnection forKey: identifier];
    
#if ! __has_feature(objc_arc)
    [newConnection release];
#endif
    
    return identifier;
}

#pragma mark -

- (NSArray *)activeConnectionIdentifiers {
    return [myConnections allKeys];
}

- (NSUInteger)numberOfActiveConnections {
    return [myConnections count];
}

#pragma mark -

- (XMLRPCConnection *)connectionForIdentifier: (NSString *)identifier {
    return [myConnections objectForKey: identifier];
}

#pragma mark -

- (void)closeConnectionForIdentifier: (NSString *)identifier {
    XMLRPCConnection *selectedConnection = [self connectionForIdentifier: identifier];
    
    if (selectedConnection) {
        [selectedConnection cancel];
        
        [myConnections removeObjectForKey: identifier];
    }
}

- (void)closeConnections {
    [[myConnections allValues] makeObjectsPerformSelector: @selector(cancel)];
    
    [myConnections removeAllObjects];
}

#pragma mark -

- (void)finalize {
    [self closeConnections];
    
    [super finalize];
}

#pragma mark -

- (void)dealloc {
    [self closeConnections];
    
#if ! __has_feature(objc_arc)
    [myConnections release];
    
    [super dealloc];
#endif
}

@end
