//
//  MQTTInspectorDetailViewController.m
//  MQTTInspector
//
//  Created by Christoph Krey on 09.11.13.
//  Copyright (c) 2013 Christoph Krey. All rights reserved.
//

#import "MQTTInspectorDetailViewController.h"
#import "Message+Create.h"
#import "Topic+Create.h"
#import "Command+Create.h"
#import "Subscription+Create.h"
#import "Publication+Create.h"
#import "MQTTInspectorLogsTableViewController.h"
#import "MQTTInspectorTopicsTableViewController.h"
#import "MQTTInspectorCommandsTableViewController.h"
#import "MQTTInspectorSubsTableViewController.h"
#import "MQTTInspectorPubsTableViewController.h"
#import "MQTTInspectorDataViewController.h"
#import "MQTTInspectorSetupPubsTableViewController.h"
#import "MQTTInspectorSetupSubsTableViewController.h"
#import "MQTTInspectorAppDelegate.h"

static Session *theSession;
static MQTTSession *theMQTTSession;

@interface MQTTInspectorDetailViewController ()
@property (weak, nonatomic) IBOutlet UIBarButtonItem *versionButton;
@property (weak, nonatomic) IBOutlet UIBarButtonItem *disconnectButton;
@property (weak, nonatomic) IBOutlet UIBarButtonItem *connectButton;
@property (weak, nonatomic) IBOutlet UIBarButtonItem *clearButton;
@property (weak, nonatomic) IBOutlet UIBarButtonItem *pubButton;
@property (weak, nonatomic) IBOutlet UIProgressView *progress;
@property (weak, nonatomic) IBOutlet UITableView *messages;
@property (weak, nonatomic) IBOutlet UITableView *subs;
@property (weak, nonatomic) IBOutlet UITableView *pubs;
@property (weak, nonatomic) IBOutlet UISegmentedControl *level;
@property (strong, nonatomic) UIPopoverController *masterPopoverController;
@property (weak, nonatomic) IBOutlet UISwitch *runningSwitch;
@property (weak, nonatomic) IBOutlet UIBarButtonItem *filterButton;

@property (strong, nonatomic) MQTTInspectorLogsTableViewController *logsTVC;
@property (strong, nonatomic) MQTTInspectorTopicsTableViewController *topicsTVC;
@property (strong, nonatomic) MQTTInspectorCommandsTableViewController *commandsTVC;
@property (strong, nonatomic) MQTTInspectorSubsTableViewController *subsTVC;
@property (strong, nonatomic) MQTTInspectorPubsTableViewController *pubsTVC;
@property (weak, nonatomic) IBOutlet UITextField *countText;

@property (strong, nonatomic) UIAlertView *alertView;
@property (strong, nonatomic) NSError *lastError;
@property (nonatomic) int errorCount;
@property (strong, nonatomic) NSManagedObjectContext *queueManagedObjectContext;
@property (nonatomic) float queueIn;
@property (nonatomic) float queueOut;

@property (nonatomic) CGRect mrect;
@property (nonatomic) CGRect srect;
@property (nonatomic) CGRect prect;

@end

@implementation MQTTInspectorDetailViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    [[NSNotificationCenter defaultCenter ]addObserver:self
                                             selector:@selector(willResign:)
                                                 name:UIApplicationWillResignActiveNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter ]addObserver:self
                                             selector:@selector(willEnter:)
                                                 name:UIApplicationWillEnterForegroundNotification
                                               object:nil];
}

- (void)willResign:(NSNotification *)notification
{
    [self disconnect:nil];
}

- (void)willEnter:(NSNotification *)notification
{
    if ([self.session.autoconnect boolValue]) {
        [self connect:nil];
    }
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [self viewChanged:nil];
    self.versionButton.title =  [NSBundle mainBundle].infoDictionary[@"CFBundleVersion"];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    [self enableButtons];
    
    /* start with organizer if no session selected */
    if (!self.session) {
        [self.masterPopoverController presentPopoverFromBarButtonItem:self.navigationController.navigationItem.backBarButtonItem
                                             permittedArrowDirections:(UIPopoverArrowDirectionAny) animated:TRUE];
    }
    [self showCount];
}

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
    if ([segue.identifier isEqualToString:@"setSessionForPub:"] || [segue.identifier isEqualToString:@"setSessionForFilter:"]) {
        if ([segue.destinationViewController respondsToSelector:@selector(setMother:)]) {
            [segue.destinationViewController performSelector:@selector(setMother:)
                                                  withObject:self];
        }
    }
    if ([segue.identifier isEqualToString:@"enlargePubs"] ||
        [segue.identifier isEqualToString:@"enlargeSubs"]) {
        
        if (segue.sourceViewController == self) {
            if ([segue.destinationViewController respondsToSelector:@selector(setSession:)]) {
                [segue.destinationViewController performSelector:@selector(setSession:)
                                                      withObject:self.session];
            }
        }
    }
    
    
    NSIndexPath *indexPath = nil;
    
    if ([sender isKindOfClass:[UITableViewCell class]]) {
        if (self.logsTVC) {
            indexPath = [self.logsTVC.tableView indexPathForCell:sender];
        }
        if (self.topicsTVC) {
            indexPath = [self.topicsTVC.tableView indexPathForCell:sender];
        }
        if (self.commandsTVC) {
            indexPath = [self.commandsTVC.tableView indexPathForCell:sender];
        }
    }
    
    if (indexPath) {
        if ([segue.identifier isEqualToString:@"setMessage:"]) {
            id theObject;
            
            if (self.logsTVC) {
                Message *message = [[self.logsTVC fetchedResultsController] objectAtIndexPath:indexPath];
                theObject = message;
            }
            if (self.topicsTVC) {
                Topic *topic = [[self.topicsTVC fetchedResultsController] objectAtIndexPath:indexPath];
                theObject = topic;
            }
            if (self.commandsTVC) {
                Command *command = [[self.commandsTVC fetchedResultsController] objectAtIndexPath:indexPath];
                theObject = command;
            }
            
            if ([segue.destinationViewController respondsToSelector:@selector(setObject:)]) {
                [segue.destinationViewController performSelector:@selector(setObject:)
                                                      withObject:theObject];
            }
        }
    }
}

- (void)publish:(Publication *)pub
{
    NSString *string = [[NSString alloc] initWithData:pub.data encoding:NSUTF8StringEncoding];
    
    // REPLACE %t with timeIntervalSince1970
    NSString *nowString = [NSString stringWithFormat:@"%.0f", [[NSDate date] timeIntervalSince1970]];
    string = [string stringByReplacingOccurrencesOfString:@"%t" withString:nowString];
    
    // REPLACE %c with effective clientId
    NSString *clientId;
    if ((!pub.belongsTo.clientid) || ([pub.belongsTo.clientid isEqualToString:@""])) {
        clientId = [NSString stringWithFormat:@"MQTTInspector-%d", getpid()];
    } else {
        clientId = pub.belongsTo.clientid;
    }
    string = [string stringByReplacingOccurrencesOfString:@"%c" withString:clientId];
    
    [self.mqttSession publishData:[string dataUsingEncoding:NSUTF8StringEncoding]
                          onTopic:pub.topic
                           retain:[pub.retained boolValue]
                              qos:[pub.qos intValue]];
}


- (NSString *)effectiveClientId
{
    NSString *clientId;
    if ((!self.session.clientid) || ([self.session.clientid isEqualToString:@""])) {
        clientId = [NSString stringWithFormat:@"MQTTInspector-%d", getpid()];
    } else {
        clientId = self.session.clientid;
    }
    return clientId;
}

- (IBAction)pan:(UIPanGestureRecognizer *)sender {
    if (sender.state == UIGestureRecognizerStateBegan) {
        [sender setTranslation:CGPointMake(self.subs.frame.size.width, self.subs.frame.size.height) inView:sender.view];
    }
    
    if (sender.state == UIGestureRecognizerStateChanged) {
        CGPoint point = [sender translationInView:sender.view];
#ifdef DEBUG
        NSLog(@"Pan: x=%f y=%f", point.x, point.y);
#endif
        CGRect mrect = self.messages.frame;
        CGRect srect = self.subs.frame;
        CGRect prect = self.pubs.frame;

        if (point.x > 8 && point.x < mrect.origin.x + mrect.size.width - 8 &&
            point.y > 8 && point.y < mrect.size.height - 8) {
            
            mrect.origin.x = point.x + 8;
            mrect.size.width = sender.view.frame.size.width - point.x - 8;
            
            srect.size.width = point.x;
            srect.size.height = point.y;
            
            prect.origin.y = point.y + 8 + srect.origin.y;
            prect.size.width = point.x;
            prect.size.height = mrect.size.height - point.y - 8;
            
            self.messages.frame = mrect;
            self.subs.frame = srect;
            self.pubs.frame = prect;
        } else {
        }
    }
}
- (IBAction)editSubs:(UILongPressGestureRecognizer *)sender {
    if (sender.state == UIGestureRecognizerStateEnded) {
        self.subs.editing = !self.subs.editing;
    }
}
- (IBAction)editPubs:(UILongPressGestureRecognizer *)sender {
    if (sender.state == UIGestureRecognizerStateEnded) {
        self.pubs.editing = !self.pubs.editing;
    }
}

- (IBAction)runningChanged:(UISwitch *)sender {
    //
}

/*
 * MQTTSession is managed here in the setSession, connect and disconnect
 */

- (void)setMqttSession:(MQTTSession *)mqttSession
{
    _mqttSession = mqttSession;
    theMQTTSession = _mqttSession;
}

#pragma mark - Managing the detail item
- (void)setSession:(Session *)session
{
    if (theSession) {
        if (theMQTTSession) {
            [theMQTTSession close];
            theMQTTSession.delegate = nil;
        }
    }
    
    _session = session;
    theSession = _session;
    
    _session.state = @(-1);
    
    if ([session.autoconnect boolValue]) {
        [self connect:nil];
    }
    
    if (self.masterPopoverController != nil) {
        [self.masterPopoverController dismissPopoverAnimated:YES];
    }
    
    [self viewChanged:nil];
    self.title = session.name;
    [self showCount];
    [self enableButtons];
}


- (IBAction)connect:(UIBarButtonItem *)sender {
    if (self.session) {
        
        if (self.mqttSession) {
            [self.mqttSession close];
            self.mqttSession.delegate = nil;
        }

        self.mqttSession = [[MQTTSession alloc] initWithClientId:[self effectiveClientId]
                                                        userName:[self.session.auth boolValue] ? self.session.user : nil
                                                        password:[self.session.auth boolValue] ? self.session.passwd : nil
                                                       keepAlive:[self.session.keepalive intValue]
                                                    cleanSession:[self.session.cleansession boolValue]
                                                            will:NO
                                                       willTopic:nil
                                                         willMsg:nil
                                                         willQoS:0
                                                  willRetainFlag:NO
                                                   protocolLevel:[self.session.protocolLevel intValue]
                                                         runLoop:[NSRunLoop currentRunLoop]
                                                         forMode:NSRunLoopCommonModes];
        self.mqttSession.delegate = self;
        
        if ([self.session.cleansession boolValue]) {
            for (Subscription *sub in self.session.hasSubs) {
                sub.state = @(0);
            }
        }
        
        [self.mqttSession connectToHost:self.session.host port:[self.session.port intValue] usingSSL:[self.session.tls boolValue]];
        
        self.title = [NSString stringWithFormat:@"%@-%@", self.session.name, [self url]];
    }
}

- (IBAction)disconnect:(UIBarButtonItem *)sender {
    if (self.session) {
        [self.mqttSession close];
        self.title = self.session.name;
    }
}

- (IBAction)viewChanged:(UISegmentedControl *)sender {
    if (self.session) {
        [self.logsTVC dismissViewControllerAnimated:YES completion:nil];
        self.logsTVC = nil;
        [self.topicsTVC dismissViewControllerAnimated:YES completion:nil];
        self.topicsTVC = nil;
        [self.commandsTVC dismissViewControllerAnimated:YES completion:nil];
        self.commandsTVC = nil;
        switch (self.level.selectedSegmentIndex) {
            case 2:
                self.commandsTVC = [[MQTTInspectorCommandsTableViewController alloc] init];
                self.commandsTVC.mother = self;
                self.commandsTVC.tableView = self.messages;
                break;
            case 1:
                self.logsTVC = [[MQTTInspectorLogsTableViewController alloc] init];
                self.logsTVC.mother = self;
                self.logsTVC.tableView = self.messages;
                break;
            case 0:
            default:
                self.topicsTVC = [[MQTTInspectorTopicsTableViewController alloc] init];
                self.topicsTVC.mother = self;
                self.topicsTVC.tableView = self.messages;
                break;
        }
    }
    [self showCount];
}

- (IBAction)clear:(UIBarButtonItem *)sender {
    if (self.session) {
        for (Message *message in self.session.hasMesssages) {
            [self.session.managedObjectContext deleteObject:message];
        }
        for (Topic *topic in self.session.hasTopics) {
            [self.session.managedObjectContext deleteObject:topic];
        }
        for (Command *command in self.session.hasCommands) {
            [self.session.managedObjectContext deleteObject:command];
        }
        NSError *error;
        if (![self.session.managedObjectContext save:&error]) {
            NSLog(@"Unresolved error %@, %@", error, [error userInfo]);
            abort();
        }
    }
    [self showCount];
}

#pragma mark - MQTTSessionDelegate
- (void)connected:(MQTTSession *)session sessionPresent:(BOOL)sessionPresent {
    if (!sessionPresent) {
        for (Subscription *sub in self.session.hasSubs) {
            sub.state = @(false);
        }
    }
}

- (void)handleEvent:(MQTTSession *)session event:(MQTTSessionEvent)eventCode error:(NSError *)error
{
#ifdef DEBUG
    NSArray *events = @[
                        @"MQTTSessionEventConnected",
                        @"MQTTSessionEventConnectionRefused",
                        @"MQTTSessionEventConnectionClosed",
                        @"MQTTSessionEventConnectionError",
                        @"MQTTSessionEventProtocolError",
                        @"MQTTSessionEventConnectionClosedByBroker"
                        ];
    
    NSLog(@"handleEvent: %@ (%ld) %@", events[eventCode % [events count]], (long)eventCode, [error description]);
    NSLog(@"session/self.mqttSession: %@/%@", session, self.mqttSession);
#endif

    if (session != self.mqttSession) {
#ifdef DEBUG
        NSLog(@"handleEvent: old Session");
#endif
        return;
    }
    
    self.session.state = @(eventCode);
    
    if ([self.session.state intValue] == MQTTSessionEventConnected) {
        self.subsTVC = [[MQTTInspectorSubsTableViewController alloc] init];
        self.subsTVC.mother = self;
        self.subsTVC.tableView = self.subs;
        
        self.pubsTVC = [[MQTTInspectorPubsTableViewController alloc] init];
        self.pubsTVC.mother = self;
        self.pubsTVC.tableView = self.pubs;
    } else {
        self.subsTVC = nil;
        UITableViewController *stvc = [[UITableViewController alloc] init];
        stvc.tableView = self.subs;
        [stvc.tableView reloadData];
        
        self.pubsTVC = nil;
        UITableViewController *ptvc = [[UITableViewController alloc] init];
        ptvc.tableView = self.pubs;
        [ptvc.tableView reloadData];
    }
    
    if ([self.session.state intValue] == MQTTSessionEventConnectionClosed) {
        MQTTInspectorAppDelegate *delegate = [UIApplication sharedApplication].delegate;
        [delegate connectionClosed];
    }
    
    if (error) {
        if ((self.lastError.domain == error.domain) && (self.lastError.code == error.code)) {
            self.errorCount++;
        } else {
            self.errorCount = 1;
        }
        if (self.errorCount == 1 && [error.domain isEqualToString:NSOSStatusErrorDomain] && error.code == errSSLClosedAbort) {
            [self performSelector:@selector(connect:) withObject:nil afterDelay:.25];
        } else {
            [MQTTInspectorDetailViewController alert:[error description]];
        }
    }
    self.lastError = error;

    [self enableButtons];
}

#define MAX_LOG 512
#define MAX_TOPIC 256
#define MAX_COMMAND 1024

- (NSManagedObjectContext *)queueManagedObjectContext
{
    if (!_queueManagedObjectContext) {
        _queueManagedObjectContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];
        [_queueManagedObjectContext setParentContext:self.session.managedObjectContext];
    }
    return _queueManagedObjectContext;
}
- (void)startQueue
{
    self.queueIn += 1;
    [self.progress setProgress:self.queueOut/self.queueIn animated:YES];
}

- (void)finishQueue
{
    while (!self.runningSwitch.on) {
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1.0]];
    }
    [self performSelectorOnMainThread:@selector(showQueue) withObject:nil waitUntilDone:NO];
}

- (void)showQueue
{
    self.queueOut += 1;
    if (self.queueIn == self.queueOut) {
        self.queueIn = 1;
        self.queueOut = 1;
    }
    [self.progress setProgress:self.queueOut/self.queueIn animated:YES];
    [self showCount];
}

- (void)showCount
{
    if (self.session) {
        switch (self.level.selectedSegmentIndex) {
            case 2:
                self.countText.text = [NSString stringWithFormat:@"%lu",
                                       (unsigned long)[self.session.hasCommands count]];
                break;
            case 1:
                self.countText.text = [NSString stringWithFormat:@"%lu",
                                       (unsigned long)[self.session.hasMesssages count]];
                break;
            case 0:
            default:
                self.countText.text = [NSString stringWithFormat:@"%lu",
                                       (unsigned long)[self.session.hasTopics count]];
                break;
        }
    } else {
        self.countText.text = @"";
    }
}

- (void)limit:(NSArray *)array max:(int)max
{
#ifdef DEBUG
    NSLog(@"#count %lu/%d", (unsigned long)[array count], max);
#endif
    
    for (NSInteger i = [array count]; i > max; i--) {
        NSManagedObject *object = array[i - 1];
#ifdef DEBUG
        NSLog(@"delete %@", object);
#endif
        [object.managedObjectContext deleteObject:object];
    }
}

- (void)newMessage:(MQTTSession *)session
              data:(NSData *)data
           onTopic:(NSString *)topic
               qos:(MQTTQosLevel)qos
          retained:(BOOL)retained
               mid:(unsigned int)mid
{
    NSDate *timestamp = [NSDate dateWithTimeIntervalSinceNow:0];
    NSString *name = self.session.name;
    NSString *attributefilter = self.session.attributefilter;
    NSString *datafilter = self.session.datafilter;
    NSString *topicfilter = self.session.topicfilter;
    BOOL includefilter = [self.session.includefilter boolValue];
    
    BOOL filter = TRUE;
    data = [self limitedData:data];
    
    NSError *error;
    
    NSString *attributes = [NSString stringWithFormat:@"q%d r%d i%u", qos, retained, mid];
    NSRegularExpression *attributeRegex =
    [NSRegularExpression regularExpressionWithPattern:attributefilter ? attributefilter : @"" options:0 error:&error];
    if (attributeRegex) {
        NSUInteger attributeMatches = [attributeRegex numberOfMatchesInString:attributes
                                                             options:0
                                                               range:NSMakeRange(0, [attributes length])];
        if ((attributeMatches == 0) == includefilter) {
#ifdef DEBUG
            NSLog(@"filter regexp %@ does not match attributes %@ %@", attributefilter, attributes, @(includefilter));
#endif
            filter = FALSE;
        }
    }
    

    NSString *dataString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    NSRegularExpression *dataRegex =
    [NSRegularExpression regularExpressionWithPattern:datafilter ? datafilter : @"" options:0 error:&error];
    if (dataRegex){
        NSUInteger dataMatches = [dataRegex numberOfMatchesInString:dataString
                                                            options:0
                                                              range:NSMakeRange(0, [dataString length])];
        if ((dataMatches == 0) == includefilter) {
#ifdef DEBUG
            NSLog(@"filter regexp %@ does not match data %@ %@", datafilter, dataString, @(includefilter));
#endif
            filter = FALSE;
        }
    }
    
    NSRegularExpression *topicRegex =
    [NSRegularExpression regularExpressionWithPattern:topicfilter ? topicfilter : @"" options:0 error:&error];
    if (topicRegex) {
        NSUInteger topicMatches = [topicRegex numberOfMatchesInString:topic
                                                              options:0
                                                                range:NSMakeRange(0, [topic length])];
        if ((topicMatches == 0) == includefilter) {
#ifdef DEBUG
            NSLog(@"filter regexp %@ does not match topic %@ %@", topicfilter, topic, @(includefilter));
#endif
            filter = FALSE;
        }
    }
    
    if (!attributeRegex || !dataRegex || !topicRegex) {
        self.filterButton.tintColor = [UIColor blueColor];
    } else {
        self.filterButton.tintColor = filter ? [UIColor greenColor] : [UIColor redColor];
    }
    
    if (filter) {
        [self startQueue];
        [self.queueManagedObjectContext performBlock:^{
            Session *mySession = [Session existSessionWithName:name
                                        inManagedObjectContext:self.queueManagedObjectContext];

#ifdef DEBUG
            NSLog(@"newLog");
#endif
            [Message messageAt:timestamp
                         topic:topic
                          data:data
                           qos:qos
                      retained:retained
                           mid:mid
                       session:mySession
        inManagedObjectContext:self.queueManagedObjectContext];
            
            [self limit:[Message allMessagesOfSession:mySession
                               inManagedObjectContext:self.queueManagedObjectContext]
                    max:MAX_LOG];
            
#ifdef DEBUG
            NSLog(@"newTopic");
#endif
            Topic *theTopic = [Topic existsTopicNamed:topic
                                              session:mySession
                               inManagedObjectContext:self.queueManagedObjectContext];
            if (theTopic) {
                theTopic.count = @([theTopic.count intValue] + 1);
                theTopic.data = data;
                theTopic.qos = @(qos);
                theTopic.mid = @(mid);
                theTopic.retained = @(retained);
                theTopic.timestamp = timestamp;
                theTopic.justupdated = theTopic.count;
            } else {
                [Topic topicNamed:topic
                        timestamp:timestamp
                             data:data
                              qos:qos
                         retained:retained
                              mid:mid
                          session:mySession
           inManagedObjectContext:self.queueManagedObjectContext];
                [self limit:[Topic allTopicsOfSession:mySession
                               inManagedObjectContext:self.queueManagedObjectContext]
                        max:MAX_TOPIC];
            }
            
            NSError *error;
            
            if (![self.queueManagedObjectContext save:NULL]) {
                NSLog(@"Unresolved error %@, %@", error, [error userInfo]);
                abort();
            }

            [self finishQueue];
        }];
    }
}

- (void)received:(MQTTSession *)session type:(int)type qos:(MQTTQosLevel)qos retained:(BOOL)retained duped:(BOOL)duped mid:(UInt16)mid data:(NSData *)data
{
    NSDate *timestamp = [NSDate dateWithTimeIntervalSinceNow:0];
    NSString *name = self.session.name;
    
    data = [self limitedData:data];

    [self startQueue];
    [self.queueManagedObjectContext performBlock:^{
#ifdef DEBUG
        NSLog(@"newCommand in");
#endif
        Session *mySession = [Session existSessionWithName:name
                                    inManagedObjectContext:self.queueManagedObjectContext];
        [Command commandAt:timestamp
                   inbound:YES
                      type:type
                     duped:duped
                       qos:qos
                  retained:retained
                       mid:mid
                      data:data
                   session:mySession
    inManagedObjectContext:self.queueManagedObjectContext];
        
        [self limit:[Command allCommandsOfSession:mySession
                           inManagedObjectContext:self.queueManagedObjectContext]
                max:MAX_COMMAND];
        
        NSError *error;
        
        if (![self.queueManagedObjectContext save:NULL]) {
            NSLog(@"Unresolved error %@, %@", error, [error userInfo]);
            abort();
        }

        [self finishQueue];
    }];
}

-(void)sending:(MQTTSession *)session type:(int)type qos:(MQTTQosLevel)qos retained:(BOOL)retained duped:(BOOL)duped mid:(UInt16)mid data:(NSData *)data
{
    NSDate *timestamp = [NSDate dateWithTimeIntervalSinceNow:0];
    NSString *name = self.session.name;
    
    data = [self limitedData:data];
    
    [self startQueue];
    [self.queueManagedObjectContext performBlock:^{
#ifdef DEBUG
        NSLog(@"newCommand out");
#endif
        Session *mySession = [Session existSessionWithName:name
                                    inManagedObjectContext:self.queueManagedObjectContext];

        
        [Command commandAt:timestamp
                   inbound:NO
                      type:type
                     duped:duped
                       qos:qos
                  retained:retained
                       mid:mid
                      data:data
                   session:mySession
    inManagedObjectContext:self.queueManagedObjectContext];
        
        [self limit:[Command allCommandsOfSession:mySession
                           inManagedObjectContext:self.queueManagedObjectContext]
                max:MAX_COMMAND];
        
        NSError *error;
        
        if (![self.queueManagedObjectContext save:NULL]) {
            NSLog(@"Unresolved error %@, %@", error, [error userInfo]);
            abort();
        }

        [self finishQueue];
    }];
}

- (void)messageDelivered:(MQTTSession *)session msgID:(UInt16)msgID
{
    //
}

- (void)buffered:(MQTTSession *)session flowingIn:(NSUInteger)flowingIn flowingOut:(NSUInteger)flowingOut
{
#ifdef DEBUG
    NSLog(@"Connection buffered i%lu o%lu", (unsigned long)flowingIn, (unsigned long)flowingOut);
#endif
    if (flowingIn + flowingOut) {
        [UIApplication sharedApplication].networkActivityIndicatorVisible = TRUE;
    } else {
        [UIApplication sharedApplication].networkActivityIndicatorVisible = FALSE;
    }
}

#pragma mark - Split view

- (void)splitViewController:(UISplitViewController *)splitController willHideViewController:(UIViewController *)viewController withBarButtonItem:(UIBarButtonItem *)barButtonItem forPopoverController:(UIPopoverController *)popoverController
{
    barButtonItem.title = @"Sessions";
    [self.navigationItem setLeftBarButtonItem:barButtonItem animated:YES];
    self.masterPopoverController = popoverController;
}

- (void)splitViewController:(UISplitViewController *)splitController willShowViewController:(UIViewController *)viewController invalidatingBarButtonItem:(UIBarButtonItem *)barButtonItem
{
    // Called when the view is shown again in the split view, invalidating the button and popover controller.
    [self.navigationItem setLeftBarButtonItem:nil animated:YES];
    self.masterPopoverController = nil;
}

- (BOOL)splitViewController:(UISplitViewController *)svc shouldHideViewController:(UIViewController *)vc inOrientation:(UIInterfaceOrientation)orientation
{
    return YES;
}

#pragma mark - Alerts

+ (void)alert:(NSString *)message
{
    UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:[NSBundle mainBundle].infoDictionary[@"CFBundleName"]
                                                        message:message
                                                       delegate:nil
                                              cancelButtonTitle:@"OK"
                                              otherButtonTitles:nil];
    [alertView show];
}


- (NSString *)url
{
    return [NSString stringWithFormat:@"%@%@%@:%@",
            ([[UIDevice currentDevice] userInterfaceIdiom] != UIUserInterfaceIdiomPad) ? @"" :
            [NSString stringWithFormat:@"%@://", [self.session.tls boolValue] ? @"mqtts" : @"mqtt"],
            [self.session.auth boolValue] ? [NSString stringWithFormat:@"%@@",
                                             self.session.user] : @"",
            self.session.host,
            self.session.port];
    
}
- (IBAction)longSub:(UILongPressGestureRecognizer *)sender {
    if (sender.state == UIGestureRecognizerStateEnded) {
        [self performSegueWithIdentifier:@"enlargeSubs" sender:sender];
    }
}
- (IBAction)longPub:(UILongPressGestureRecognizer *)sender {
    if (sender.state == UIGestureRecognizerStateEnded) {
        [self performSegueWithIdentifier:@"enlargePubs" sender:sender];
    }
}

- (void)enableButtons
{
#ifdef DEBUG
    NSLog(@"self.session.state: %@", self.session.state);
#endif

    if (self.session) {
        self.level.enabled = TRUE;
        self.clearButton.enabled = TRUE;
        self.filterButton.enabled = TRUE;

        switch ([self.session.state intValue]) {
        case MQTTSessionEventConnected:
            self.connectButton.enabled = FALSE;
            self.disconnectButton.enabled = TRUE;
            self.pubButton.enabled = TRUE;
            break;
            
        default:
            self.connectButton.enabled = TRUE;
            self.disconnectButton.enabled = FALSE;
            self.pubButton.enabled = FALSE;
            break;
        }
    } else {
        self.level.enabled = FALSE;
        self.clearButton.enabled = FALSE;
        self.filterButton.enabled = FALSE;
    }
}

- (NSData *)limitedData:(NSData *)data
{
    NSData *limitedData = data;
    int limit = [self.session.sizelimit intValue];
    if (limit) {
        limitedData = [data subdataWithRange:NSMakeRange(0, MIN(data.length, limit))];
    }
    return limitedData;
}

@end
