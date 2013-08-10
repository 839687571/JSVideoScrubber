//
//  JSViewController.m
//  JSVideoScrubber
//
//  Created by jaminschubert on 9/8/12.
//  Copyright (c) 2012 jaminschubert. All rights reserved.
//

#import "TTTAttributedLabel.h"
#import "JSVideoScrubber.h"
#import "JSSimViewController.h"

@interface UIRefreshControl(JSDelays)

- (void) endRefreshingAfterDelay:(CGFloat) f;

@end

@implementation UIRefreshControl (JSDelays)

- (void) endRefreshingAfterDelay:(CGFloat) f
{
    dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC));
    dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
        [self endRefreshing];
    });
}

@end

@interface JSSimViewController () <UITableViewDelegate, UITableViewDataSource, UIImagePickerControllerDelegate>

@property (strong, nonatomic) UITableViewController *tableViewController;
@property (strong, nonatomic) UIRefreshControl *refreshControl;

@property (strong, nonatomic) IBOutlet TTTAttributedLabel *instructions;
@property (weak, nonatomic) IBOutlet JSVideoScrubber *jsVideoScrubber;
@property (strong, nonatomic) IBOutlet UITableView *videosTableView;

@property (weak, nonatomic) IBOutlet UILabel *duration;
@property (weak, nonatomic) IBOutlet UILabel *offset;
@property (strong, nonatomic) NSString *documentDirectory;
@property (strong, nonatomic) NSArray *assetPaths;

@property (strong, nonatomic) NSIndexPath *currentSelection;

@end

@implementation JSSimViewController

@synthesize jsVideoScrubber;

#pragma mark - UIView

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    self.tableViewController = [[UITableViewController alloc] init];
    self.tableViewController.tableView = self.videosTableView;
    
    [self addChildViewController:self.tableViewController];
    [self.tableViewController didMoveToParentViewController:self];
    
    self.refreshControl = [[UIRefreshControl alloc] init];
    self.tableViewController.refreshControl = self.refreshControl;
    [self.refreshControl addTarget:self action:@selector(handleRefresh:) forControlEvents:UIControlEventValueChanged];
    
    self.documentDirectory = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) lastObject];
}

- (void)viewDidUnload
{
    [self setJsVideoScrubber:nil];
    [self setDuration:nil];
    [self setOffset:nil];
    [self setInstructions:nil];
    [self setVideosTableView:nil];
    
    [super viewDidUnload];
}

- (void) viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];

    self.duration.text = @"Duration: 00:00";
    self.offset.text = @"Offset: 00:00";
    
    [self setupInstructions];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [self updateTable];
    });
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
    return (interfaceOrientation != UIInterfaceOrientationPortraitUpsideDown);
}

- (void) touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event
{
    [self.view endEditing:YES];
    [super touchesBegan:touches withEvent:event];
}

- (BOOL)prefersStatusBarHidden
{
    return YES;
}

#pragma mark - UITableViewDelegate / UITableViewDataSource

-(NSInteger) numberOfSectionsInTableView:(UITableView *)tableView
{
    return 1;
}

-(NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return [self.assetPaths count];
}

- (NSString *) tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    return @"Assets - Pull me to refresh!";
}

-(UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    static NSString *cellIdentifier = @"JSAssetCellId";
    
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellIdentifier];
    
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:cellIdentifier];
    }
    
    cell.textLabel.text = [self.assetPaths[indexPath.row] lastPathComponent];
    return cell;
}

-(void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (self.currentSelection && (self.currentSelection.row == indexPath.row)) {
        return;
    }
    
    NSString *path = self.assetPaths[indexPath.row];
    NSURL* url = [NSURL fileURLWithPath:[self.documentDirectory stringByAppendingPathComponent:path]];
    AVURLAsset* asset = [AVURLAsset URLAssetWithURL:url options:nil];
    
    __weak JSSimViewController *ref = self;
    
    NSArray *keys = [NSArray arrayWithObjects:@"tracks", @"duration", nil];
    [asset loadValuesAsynchronouslyForKeys:keys completionHandler:^(void) {
        self.duration.text = @"Duration: N/A";
        self.offset.text = @"Offset: N/A";
        
        [ref setupJSVideoScrubber:asset];
        
        double total = CMTimeGetSeconds(self.jsVideoScrubber.duration);
        
        int min = (int)total / 60;
        int seconds = (int)total % 60;
        self.duration.text = [NSString stringWithFormat:@"Duration: %02d:%02d", min, seconds];
        
        [ref updateOffsetLabel:self.jsVideoScrubber];
        [ref.jsVideoScrubber addTarget:self action:@selector(updateOffsetLabel:) forControlEvents:UIControlEventValueChanged];
        ref.currentSelection = indexPath;
    }];
}

#pragma mark - UIRefresh Cheat

- (void) handleRefresh:(id) sender
{
    [self updateTable];
}

#pragma MARK - TTTAttributedLabel 

- (void)attributedLabel:(TTTAttributedLabel *)label didSelectLinkWithURL:(NSURL *)url
{
    [[UIApplication sharedApplication] openURL:url];
}

#pragma mark - Support

- (void) setupInstructions
{
    //IB font settings didnt take...
    self.instructions.font = [UIFont fontWithName:@"Helvetica" size:12.0f];
    
    self.instructions.text = @"1. Use the excellent utility SimPholders to locate the application documents directory for this app in the simulator, and drop in your .mov files.\n2. Tap on the file name in the table to load the video in the scrubber.";
    NSRange r = [self.instructions.text rangeOfString:@"SimPholders"];
    [self.instructions addLinkToURL:[NSURL URLWithString:@"http://simpholders.com/"] withRange:r];
}

- (void) setupJSVideoScrubber:(AVAsset *) asset
{
    [self.jsVideoScrubber setupControlWithAVAsset:asset];
}

- (void) updateOffsetLabel:(JSVideoScrubber *) scrubber
{
    int min = (int)self.jsVideoScrubber.offset / 60;
    int seconds = (int)self.jsVideoScrubber.offset % 60;
    self.offset.text = [NSString stringWithFormat:@"Offset: %02d:%02d", min, seconds];
}


- (void) updateTable
{
    [self scanForAssets];
    [self.videosTableView reloadData];
    [self.refreshControl endRefreshingAfterDelay:0.1];
}

- (void) scanForAssets
{        
    NSError *error = nil;
    NSArray *contents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:self.documentDirectory error:&error];
    
    if (!contents) {
        [[[UIAlertView alloc] initWithTitle:@"Error" message:@"Error occured scanning docs directory" delegate:nil cancelButtonTitle:@"Ok" otherButtonTitles:nil] show];
        NSLog(@"error scanning directory: %@", error);
        return;
    }
    
    NSPredicate *fltr = [NSPredicate predicateWithFormat:@"self ENDSWITH '.mov'"];
    NSArray *paths = [contents filteredArrayUsingPredicate:fltr];
    
    self.assetPaths = [NSArray arrayWithArray:paths];
}
@end
