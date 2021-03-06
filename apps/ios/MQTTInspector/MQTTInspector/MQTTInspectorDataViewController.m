//
//  MQTTInspectorDataViewController.m
//  MQTTInspector
//
//  Created by Christoph Krey on 14.11.13.
//  Copyright (c) 2013 Christoph Krey. All rights reserved.
//

#define SB

#import "MQTTInspectorDataViewController.h"
#ifdef SB
#import "SBJson4.h"
#endif

@interface MQTTInspectorDataViewController ()
@property (weak, nonatomic) IBOutlet UITextView *dataTextView;
@property (weak, nonatomic) IBOutlet UITextField *attributesTextView;
@property (weak, nonatomic) IBOutlet UIImageView *justupdatedImageView;
@property (weak, nonatomic) IBOutlet UISwitch *formatSwitch;

@end

@implementation MQTTInspectorDataViewController

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    
    self.formatSwitch.on = TRUE;
    
    if ([self.object isKindOfClass:[Topic class]]) {
        Topic *topic = (Topic *)self.object;
        [topic addObserver:self forKeyPath:@"justupdated"
                        options:NSKeyValueObservingOptionNew | NSKeyValueObservingOptionInitial
                        context:nil];
        [topic addObserver:self forKeyPath:@"timestamp"
                        options:NSKeyValueObservingOptionNew | NSKeyValueObservingOptionInitial
                        context:nil];
        [topic addObserver:self forKeyPath:@"qos"
                        options:NSKeyValueObservingOptionNew | NSKeyValueObservingOptionInitial
                        context:nil];
        [topic addObserver:self forKeyPath:@"retain"
                        options:NSKeyValueObservingOptionNew | NSKeyValueObservingOptionInitial
                        context:nil];
        [topic addObserver:self forKeyPath:@"mid"
                        options:NSKeyValueObservingOptionNew | NSKeyValueObservingOptionInitial
                        context:nil];
        [topic addObserver:self forKeyPath:@"count"
                        options:NSKeyValueObservingOptionNew | NSKeyValueObservingOptionInitial
                        context:nil];
        [topic addObserver:self forKeyPath:@"data"
                        options:NSKeyValueObservingOptionNew | NSKeyValueObservingOptionInitial
                        context:nil];
    }

    [self show];
}

- (void)show
{
    if ([self.object isKindOfClass:[Topic class]]) {
        Topic *topic = (Topic *)self.object;
        self.title = [topic attributeTextPart2];
        self.attributesTextView.text = [NSString stringWithFormat:@"%@ %@",
                                        [topic attributeTextPart1],
                                        [topic attributeTextPart3]];
        self.dataTextView.text = [self dataToPrettyString:topic.data];
    } else if ([self.object isKindOfClass:[Message class]]) {
        Message *message = (Message *)self.object;
        self.title = [message attributeTextPart2];
        self.attributesTextView.text = [NSString stringWithFormat:@"%@ %@",
                                        [message attributeTextPart1],
                                        [message attributeTextPart3]];
        self.dataTextView.text = [self dataToPrettyString:message.data];
    } else if ([self.object isKindOfClass:[Command class]]) {
        Command *command = (Command *)self.object;
        self.title = [command attributeTextPart2];
        self.attributesTextView.text = [NSString stringWithFormat:@"%@ %@",
                                        [command attributeTextPart1],
                                        [command attributeTextPart3]];
        self.dataTextView.text = [self dataToPrettyString:command.data];
    }
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    if ([self.object isKindOfClass:[Topic class]]) {
        Topic *topic = (Topic *)self.object;
        [topic removeObserver:self forKeyPath:@"data"];
        [topic removeObserver:self forKeyPath:@"count"];
        [topic removeObserver:self forKeyPath:@"mid"];
        [topic removeObserver:self forKeyPath:@"retain"];
        [topic removeObserver:self forKeyPath:@"qos"];
        [topic removeObserver:self forKeyPath:@"timestamp"];
        [topic removeObserver:self forKeyPath:@"justupdated"];
    }
}

- (IBAction)formatChanged:(UISwitch *)sender {
    [self show];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    
#ifdef DEBUG
    NSLog(@"observeValueForKeyPath %@ %@ %@ %@", keyPath, object, change, context);
#endif
    Topic *topic = (Topic *)object;
    
    if ([keyPath isEqualToString:@"justupdated"]) {
        self.justupdatedImageView.image = nil;
        self.justupdatedImageView.animationImages = nil;
        [self.justupdatedImageView stopAnimating];
        
        if ([topic isJustupdated]) {
            self.justupdatedImageView.image = [UIImage imageNamed:@"new.png"];
            self.justupdatedImageView.animationImages = @[[UIImage imageNamed:@"new.png"],
                                                          [UIImage imageNamed:@"old.png"]];
            self.justupdatedImageView.animationDuration = 1.0;
            [self.justupdatedImageView startAnimating];
            [topic performSelector:@selector(setOld) withObject:nil afterDelay:3.0];
        } else  {
            self.justupdatedImageView.image = [UIImage imageNamed:@"old.png"];
        }
    }
    
    [self show];
}

- (NSString *)dataToPrettyString:(NSData *)data
{
    if (self.formatSwitch.isOn) {
        __block id json;
#ifdef SB
        SBJson4Parser *parser = [SBJson4Parser parserWithBlock:^(id item, BOOL *stop){
#ifdef DEBUG
            NSLog(@"parser value %@", item);
#endif
            json = item;
        }
                                                allowMultiRoot:NO
                                               unwrapRootArray:NO
                                                  errorHandler:^(NSError *error) {
#ifdef DEBUG
                                                      NSLog(@"parser error %@", error);
#endif
                                                      
        }];
        SBJson4ParserStatus status = [parser parse:data];
        if (status == SBJson4ParserComplete) {
            SBJson4Writer *writer = [[SBJson4Writer alloc] init];
            writer.humanReadable = YES;
            writer.sortKeys = YES;
            self.formatSwitch.enabled = TRUE;
            return [writer stringWithObject:json];
        } else {
            self.formatSwitch.enabled = FALSE;
            return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        }
        
#else // SB
        NSError *error;
        NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
        if (dict) {
            NSData *prettyData = [NSJSONSerialization dataWithJSONObject:dict
                                                                 options:NSJSONWritingPrettyPrinted
                                                                   error:&error];
            NSString *message = [[NSString alloc] init];
            for (int i = 0; i < prettyData.length; i++) {
                char c;
                [prettyData getBytes:&c range:NSMakeRange(i, 1)];
                message = [message stringByAppendingFormat:@"%c", c];
            }
            self.formatSwitch.enabled = TRUE;
            return message;
        } else {
            self.formatSwitch.enabled = FALSE;
            return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        }
#endif // SB
    } else {
        return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    }
}

@end
