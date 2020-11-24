//
//  EaseConversationsViewController.m
//  EaseIMKit
//
//  Created by 杜洁鹏 on 2020/10/29.
//

#import "EaseConversationsViewController.h"
#import "EaseHeaders.h"
#import "EaseConversationViewModel.h"
#import "EaseConversationCell.h"
#import "EaseConversationCellModel.h"
#import "EMConversation+EaseUI.h"

@interface EaseConversationsViewController ()
<
    UITableViewDelegate,
    UITableViewDataSource,
    EMContactManagerDelegate,
    EMChatManagerDelegate,
    EMGroupManagerDelegate
>
{
    dispatch_queue_t _loadDataQueue;
}
@property (nonatomic, strong) UIView *blankPerchView;

@end

@implementation EaseConversationsViewController

@synthesize viewModel = _viewModel;

- (instancetype)initWithModel:(EaseConversationViewModel *)aModel{
    if (self = [super initWithModel:aModel]) {
        _viewModel = aModel;
        _loadDataQueue = dispatch_queue_create("com.easemob.easeui.conversations.queue", 0);
        [[EMClient sharedClient].contactManager addDelegate:self delegateQueue:nil];
        [[EMClient sharedClient].groupManager addDelegate:self delegateQueue:nil];
        [[EMClient sharedClient].chatManager addDelegate:self delegateQueue:nil];
    }
    
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refreshTabView) name:CONVERSATIONLIST_UPDATE object:nil];
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}


#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    if (self.delegate && [self.delegate respondsToSelector:@selector(easeNumberOfSectionsInTableView:)]) {
        return [self.delegate easeNumberOfSectionsInTableView:tableView];
    }
    
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    
    if (self.delegate && [self.delegate respondsToSelector:@selector(easeTableView:numberOfRowsInSection:)]) {
        return [self.delegate easeTableView:tableView numberOfRowsInSection:section];
    }
    
    return [self.dataAry count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (self.delegate && [self.delegate respondsToSelector:@selector(easeTableView:cellForRowAtIndexPath:)]) {
        return [self.delegate easeTableView:tableView cellForRowAtIndexPath:indexPath];
    }
    
    EaseConversationCell *cell = [EaseConversationCell tableView:tableView cellViewModel:_viewModel];
    
    EaseConversationCellModel *model = self.dataAry[indexPath.row];
    
    cell.model = model;
    if (model.isTop) {
        cell.backgroundColor = UIColor.redColor;
    }else {
        cell.backgroundColor = _viewModel.cellBgColor;
    }
    
    return cell;
}

#pragma mark - Table view delegate

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath API_AVAILABLE(ios(11.0)) API_UNAVAILABLE(tvos)
{
    EaseConversationCellModel *model = [self.dataAry objectAtIndex:indexPath.row];
    
    __weak typeof(self) weakself = self;
    
    UIContextualAction *deleteAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive
                                                                               title:@"删除"
                                                                             handler:^(UIContextualAction * _Nonnull action, __kindof UIView * _Nonnull sourceView, void (^ _Nonnull completionHandler)(BOOL))
    {
        [weakself _deleteConversation:indexPath];
        [weakself refreshTabView];
    }];
    
    UIContextualAction *topAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal
                                                                            title:!model.isTop ? @"置顶" : @"取消置顶"
                                                                          handler:^(UIContextualAction * _Nonnull action, __kindof UIView * _Nonnull sourceView, void (^ _Nonnull completionHandler)(BOOL))
    {
        EMConversation *conversation = [EMClient.sharedClient.chatManager getConversation:model.itemId
                                                                                     type:model.type
                                                                         createIfNotExist:YES];
        [conversation setTop:!model.isTop];
        [weakself refreshTabView];
    }];
    
    NSArray *swipeActions = @[deleteAction, topAction];
    if (self.delegate && [self.delegate respondsToSelector:@selector(easeTableView:trailingSwipeActionsForRowAtIndexPath:actions:)]) {
        swipeActions = [self.delegate easeTableView:tableView trailingSwipeActionsForRowAtIndexPath:indexPath actions:swipeActions];
    }

    UISwipeActionsConfiguration *actions = [UISwipeActionsConfiguration configurationWithActions:swipeActions];
    actions.performsFirstActionWithFullSwipe = NO;
    return actions;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (self.delegate && [self.delegate respondsToSelector:@selector(easeTableView:didSelectRowAtIndexPath:)]) {
        return [self.delegate easeTableView:tableView didSelectRowAtIndexPath:indexPath];
    }
}


#pragma mark - EMChatManagerDelegate

- (void)messagesDidRecall:(NSArray *)aMessages {
    [self _loadAllConversationsFromDB];
}

- (void)messagesDidReceive:(NSArray *)aMessages
{
    [self _loadAllConversationsFromDB];
}

#pragma mark - UIMenuController

//删除会话
- (void)_deleteConversation:(NSIndexPath *)indexPath
{
    __weak typeof(self) weakSelf = self;
    NSInteger row = indexPath.row;
    EaseConversationCellModel *model = [self.dataAry objectAtIndex:row];
    [[EMClient sharedClient].chatManager deleteConversation:model.itemId
                                           isDeleteMessages:YES
                                                 completion:^(NSString *aConversationId, EMError *aError) {
        if (!aError) {
            [weakSelf.dataAry removeObjectAtIndex:row];
            [weakSelf.tableView reloadData];
            [weakSelf _updateBackView];
        }
    }];
}

- (void)_loadAllConversationsFromDB
{
    __weak typeof(self) weakSelf = self;
    dispatch_async(_loadDataQueue, ^{
        NSMutableArray<id<EaseUserDelegate>> *totals = [NSMutableArray<id<EaseUserDelegate>> array];
        
        NSArray *conversations = [EMClient.sharedClient.chatManager getAllConversations];
        
        NSMutableArray *convs = [NSMutableArray array];
        NSMutableArray *topConvs = [NSMutableArray array];
        
        for (EMConversation *conv in conversations) {
            EaseConversationCellModel *item = [[EaseConversationCellModel alloc] initWithConversation:conv];
            if (weakSelf.delegate && [weakSelf.delegate respondsToSelector:@selector(easeUserDelegateAtConversationId:conversationType:)]) {
                item.userDelegate = [weakSelf.delegate easeUserDelegateAtConversationId:conv.conversationId conversationType:conv.type];
            }
            
            if (item.isTop) {
                [topConvs addObject:item];
            }else {
                [convs addObject:item];
            }
        }
        
        NSArray *normalConvList = [convs sortedArrayUsingComparator:
                                   ^NSComparisonResult(EaseConversationCellModel *obj1, EaseConversationCellModel *obj2)
        {
            if (obj1.lastestUpdateTime > obj2.lastestUpdateTime) {
                return(NSComparisonResult)NSOrderedAscending;
            }else {
                return(NSComparisonResult)NSOrderedDescending;
            }
        }];
        
        NSArray *topConvList = [topConvs sortedArrayUsingComparator:
                                ^NSComparisonResult(EaseConversationCellModel *obj1, EaseConversationCellModel *obj2)
        {
            if (obj1.lastestUpdateTime > obj2.lastestUpdateTime) {
                return(NSComparisonResult)NSOrderedAscending;
            }else {
                return(NSComparisonResult)NSOrderedDescending;
            }
        }];
        
        [totals addObjectsFromArray:topConvList];
        [totals addObjectsFromArray:normalConvList];
        
        weakSelf.dataAry = (NSMutableArray *)totals;
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf endRefresh];
            [weakSelf _updateBackView];
        });
    });
}

- (void)refreshTabView
{
    [self _loadAllConversationsFromDB];
}

- (void)_updateBackView {
    if (self.dataAry.count == 0) {
        [self.tableView.backgroundView setHidden:NO];
    }else {
        [self.tableView.backgroundView setHidden:YES];
    }
}

@end