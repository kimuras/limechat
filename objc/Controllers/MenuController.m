#import "MenuController.h"
#import <WebKit/WebKit.h>
#import "IRC.h"
#import "IRCWorld.h"
#import "IRCClient.h"
#import "IRCChannel.h"
#import "ServerDialog.h"
#import "ChannelDialog.h"
#import "Regex.h"
#import "URLOpener.h"
#import "GTMNSString+URLArguments.h"
#import "NSPasteboardHelper.h"


#define CONNECTED				(u && u.isConnected)
#define NOT_CONNECTED			(u && !u.isConnected)
#define LOGIN					(u && u.isLoggedIn)
#define ACTIVE					(LOGIN && c && c.isActive)
#define NOT_ACTIVE				(LOGIN && c && !c.isActive)
#define ACTIVE_CHANNEL			(ACTIVE && c.isChannel)
#define ACTIVE_CHANTALK			(ACTIVE && (c.isChannel || c.isTalk))
#define LOGIN_CHANTALK			(LOGIN && (!c || c.isChannel || c.isTalk))
#define OP						(ACTIVE_CHANNEL && c.isOp)
#define KEY_WINDOW				([window isKeyWindow])


//@class WebHTMLView;


@interface MenuController (Private)
- (LogView*)currentWebView;
- (BOOL)checkSelectedMembers:(NSMenuItem*)item;
@end


@implementation MenuController

@synthesize app;
@synthesize world;
@synthesize window;
@synthesize text;
@synthesize tree;
@synthesize memberList;

@synthesize pointedUrl;
@synthesize pointedAddress;
@synthesize pointedNick;
@synthesize pointedChannelName;

- (id)init
{
	if (self = [super init]) {
		serverDialogs = [NSMutableArray new];
		channelDialogs = [NSMutableArray new];
		pasteClients = [NSMutableArray new];
	}
	return self;
}

- (void)dealloc
{
	[pointedUrl release];
	[pointedAddress release];
	[pointedNick release];
	[pointedChannelName release];
	
	[preferencesController release];
	[serverDialogs release];
	[channelDialogs release];
	[pasteClients release];
	
	[nickSheet release];
	[modeSheet release];
	[super dealloc];
}

- (void)terminate
{
	for (ServerDialog* d in serverDialogs) {
		[d close];
	}
	for (ChannelDialog* d in channelDialogs) {
		[d close];
	}
	if (preferencesController) {
		[preferencesController close];
	}
}

- (BOOL)isNickMenu:(NSMenuItem*)item
{
	if (!item) return NO;
	NSInteger tag = item.tag;
	return 2500 <= tag && tag < 3000;
}

- (BOOL)validateMenuItem:(NSMenuItem *)item
{
	IRCClient* u = world.selectedClient;
	IRCChannel* c = world.selectedChannel;
	
	NSInteger tag = item.tag;
	if ([self isNickMenu:item]) tag -= 500;
	
	switch (tag) {
		case 102:	// preferences
		case 104:	// auto op
		case 201:	// dcc
			return YES;
		case 202:	// close current panel without confirmation
			return KEY_WINDOW && u && !c;
		case 203:	// close window / close current panel
			if (KEY_WINDOW) {
				[closeWindowItem setTitle:_(@"CloseCurrentPanelMenuTitle")];
			}
			else {
				[closeWindowItem setTitle:_(@"CloseWindowMenuTitle")];
			}
			return YES;
		case 313:	// paste
		{
			if (![[NSPasteboard generalPasteboard] hasStringContent]) {
				return NO;
			}
			NSWindow* win = [NSApp keyWindow];
			if (!win) return NO;
			id t = [win firstResponder];
			if (!t) return NO;
			if (win == window) {
				return YES;
			}
			else if ([t respondsToSelector:@selector(paste:)]) {
				if ([t respondsToSelector:@selector(validateMenuItem:)]) {
					return [t validateMenuItem:item];
				}
				return YES;
			}
		}
		case 324:	// use selection for find
		{
			NSWindow* win = [NSApp keyWindow];
			if (!win) return NO;
			id t = [win firstResponder];
			if (!t) return NO;
			NSString* klass = [t className];
			if ([klass isEqualToString:@"WebHTMLView"]) {
				return YES;
			}
			if ([t respondsToSelector:@selector(writeSelectionToPasteboard:type:)]) {
				return YES;
			}
			return NO;
		}
		case 331:	// search in google
		{
			LogView* web = [self currentWebView];
			if (!web) return NO;
			return [web hasSelection];
		}
		case 332:	// paste my address
		{
			if (![window isKeyWindow]) return NO;
			id t = [window firstResponder];
			if (!t) return NO;
			IRCClient* u = world.selectedClient;
			if (!u || !u.myAddress) return NO;
			return YES;
		}
		case 333:	// paste dialog
		case 334:	// copy log as html
		case 335:	// copy console log as html
		case 411:	// mark scrollback
		case 412:	// clear mark
		case 413:	// mark all as read
		case 414:	// go to mark
			return YES;
		case 421:	// make text bigger
			return [world.consoleLog.view canMakeTextLarger];
		case 422:	// make text smaller
			return [world.consoleLog.view canMakeTextSmaller];
		case 443:	// reload theme
			return YES;
			
		case 501:	// connect
			return NOT_CONNECTED;
		case 502:	// disconnect
			return u && (u.isConnected || u.isConnecting);
		case 503:	// cancel isReconnecting
			return u && u.isReconnecting;
		case 511:	// nick
		case 519:	// channel list
			return LOGIN;
		case 521:	// add server
			return YES;
		case 522:	// copy server
			return u != nil;
		case 523:	// delete server
			return NOT_CONNECTED;
		case 541:	// server property
		case 542:	// server auto op
			return u != nil;
			
		case 601:	// join
			return LOGIN && NOT_ACTIVE && c.isChannel;
		case 602:	// leave
			return ACTIVE;
		case 611:	// mode
			return ACTIVE_CHANNEL;
		case 612:	// topic
			return ACTIVE_CHANNEL;
		case 651:	// add channel
			return u != nil;
		case 652:	// delete channel
			return c != nil;
		case 653:	// channel property
			return c && c.isChannel;
		case 654:	// channel auto op
			return c && c.isChannel;
			
		case 802:
			return YES;
			
		// for members
		case 2001:	// whois
		case 2002:	// talk
			return LOGIN_CHANTALK && [self checkSelectedMembers:item];
		case 2003:	// give op
		case 2004:	// deop
		case 2031:	// kick
		case 2041:	// give voice
		case 2042:	// devoice
			return OP && [self checkSelectedMembers:item];
		case 2011:	// dcc send file
			return LOGIN_CHANTALK && [self checkSelectedMembers:item] && u.myAddress;
		case 2021:	// register to auto op
			return [self checkSelectedMembers:item];
		case 2101 ... 2105:	// CTCP
			return LOGIN_CHANTALK && [self checkSelectedMembers:item];
		case 2032:	// ban
		case 2033:	// kick & ban
			return OP && [self checkSelectedMembers:item] && c.isWhoInit;
			
		case 3001:	// copy url
		case 3002:	// copy address
		case 3201:	// open channel
		case 3301:	// join channel
			return YES;
	}
	
	return YES;
}

#pragma mark -
#pragma mark Utilities

- (LogView*)currentWebView
{
	id t = [window firstResponder];
	while ([t isKindOfClass:[NSView class]]) {
		if ([t isKindOfClass:[LogView class]]) {
			return t;
		}
		t = [t superview];
	}
	return nil;
}

- (BOOL)checkSelectedMembers:(NSMenuItem*)item
{
	if ([self isNickMenu:item]) {
		return pointedNick != nil;
	}
	else {
		return [memberList countSelectedRows] > 0;
	}
}

- (NSArray*)selectedMembers:(NSMenuItem*)sender
{
	IRCChannel* c = world.selectedChannel;
	if (!c) {
		if ([self isNickMenu:sender]) {
			IRCUser* m = [[IRCUser new] autorelease];
			m.nick = pointedNick;
			return [NSArray arrayWithObject:m];
		}
		else {
			return [NSArray array];
		}
	}
	else {
		if ([self isNickMenu:sender]) {
			IRCUser* m = [c findMember:pointedNick];
			if (m) {
				return [NSArray arrayWithObject:m];
			}
			else {
				return [NSArray array];
			}
		}
		else {
			NSMutableArray* ary = [NSMutableArray array];
			NSIndexSet* indexes = [memberList selectedRowIndexes];
			NSUInteger n = [indexes firstIndex];
			while (n != NSNotFound) {
				IRCUser* m = [c memberAtIndex:n];
				[ary addObject:m];
				n = [indexes indexGreaterThanIndex:n];
			}
			return ary;
		}
	}
}

- (void)deselectMembers:(NSMenuItem*)sender
{
	if (![self isNickMenu:sender]) {
		[memberList deselectAll:nil];
	}
}

#pragma mark -
#pragma mark Menu Items

- (void)onPreferences:(id)sender
{
	if (!preferencesController) {
		preferencesController = [PreferencesController new];
		preferencesController.delegate = self;
	}
	[preferencesController show];
}

- (void)preferencesDialogWillClose:(PreferencesController*)sender
{
	[world preferencesChanged];
}

- (void)onAutoOp:(id)sender
{
}

- (void)onDcc:(id)sender
{
}

- (void)onCloseWindow:(id)sender
{
	if ([window isKeyWindow]) {
	}
	else {
		[[NSApp keyWindow] performClose:nil];
	}
}

- (void)onCloseCurrentPanel:(id)sender
{
}

- (void)onPaste:(id)sender
{
	NSPasteboard* pb = [NSPasteboard generalPasteboard];
	if (![pb hasStringContent]) return;
	
	NSWindow* win = [NSApp keyWindow];
	if (!win) return;
	id t = [win firstResponder];
	if (!t) return;
	
	if (win == window) {
		NSString* s = [pb stringContent];
		if (!s.length) return;
		
		NSText* e = [win fieldEditor:NO forObject:text];
		[e paste:nil];
	}
	else {
		if ([t respondsToSelector:@selector(paste:)]) {
			BOOL validated = YES;
			if ([t respondsToSelector:@selector(validateMenuItem:)]) {
				validated = [t validateMenuItem:sender];
			}
			if (validated) {
				[t paste:sender];
			}
		}
	}
}

- (void)onPasteDialog:(id)sender
{
}

- (void)onUseSelectionForFind:(id)sender
{
	NSWindow* win = [NSApp keyWindow];
	if (!win) return;
	id t = [win firstResponder];
	if (!t) return;
	
	NSString* klass = [t className];
	if ([klass isEqualToString:@"WebHTMLView"]) {
		while ([t isKindOfClass:[NSView class]]) {
			if ([t isKindOfClass:[LogView class]]) {
				NSPasteboard* pb = [NSPasteboard pasteboardWithName:NSFindPboard];
				[pb setStringContent:[t selection]];
			}
			t = [t superview];
		}
	}
	else if ([t respondsToSelector:@selector(writeSelectionToPasteboard:type:)]) {
		NSPasteboard* pb = [NSPasteboard pasteboardWithName:NSFindPboard];
		[pb declareTypes:[NSArray arrayWithObject:NSStringPboardType] owner:nil];
		[t writeSelectionToPasteboard:pb type:NSStringPboardType];
	}
}

- (void)onPasteMyAddress:(id)sender
{
}

- (void)onSearchWeb:(id)sender
{
	LogView* web = [self currentWebView];
	if (!web) return;
	NSString* s = [web selection];
	if (s.length) {
		s = [s gtm_stringByEscapingForURLArgument];
		NSString* urlStr = [NSString stringWithFormat:@"http://www.google.com/search?ie=UTF-8&q=%@", s];
		[URLOpener open:[NSURL URLWithString:urlStr]];
	}
}

- (void)onCopyLogAsHtml:(id)sender
{
	IRCTreeItem* sel = world.selected;
	if (!sel) return;
	NSString* s = [sel.log.view contentString];
	[[NSPasteboard generalPasteboard] setStringContent:s];
}

- (void)onCopyConsoleLogAsHtml:(id)sender
{
	NSString* s = [world.consoleLog.view contentString];
	[[NSPasteboard generalPasteboard] setStringContent:s];
}

- (void)onMarkScrollback:(id)sender
{
	IRCTreeItem* sel = world.selected;
	if (!sel) return;
	[sel.log mark];
}

- (void)onClearMark:(id)sender
{
	IRCTreeItem* sel = world.selected;
	if (!sel) return;
	[sel.log unmark];
}

- (void)onGoToMark:(id)sender
{
	IRCTreeItem* sel = world.selected;
	if (!sel) return;
	[sel.log goToMark];
}

- (void)onMarkAllAsRead:(id)sender
{
	[world markAllAsRead];
}

- (void)onMarkAllAsReadAndMarkAllScrollbacks:(id)sender
{
	[world markAllAsRead];
	[world markAllScrollbacks];
}

- (void)onMakeTextBigger:(id)sender
{
	[world changeTextSize:YES];
}

- (void)onMakeTextSmaller:(id)sender
{
	[world changeTextSize:NO];
}

- (void)onReloadTheme:(id)sender
{
	[world reloadTheme];
}

- (void)onConnect:(id)sender
{
	IRCClient* u = world.selectedClient;
	if (!u) return;
	[u connect];
}

- (void)onDisconnect:(id)sender
{
	IRCClient* u = world.selectedClient;
	if (!u) return;
	[u quit];
}

- (void)onCancelReconnecting:(id)sender
{
	IRCClient* u = world.selectedClient;
	if (!u) return;
	[u cancelReconnect];
}

- (void)onNick:(id)sender
{
	if (nickSheet) return;
	
	IRCClient* u = world.selectedClient;
	if (!u) return;
	
	nickSheet = [NickSheet new];
	nickSheet.delegate = self;
	nickSheet.window = window;
	nickSheet.uid = u.uid;
	[nickSheet start:u.myNick];
}

- (void)nickSheet:(NickSheet*)sender didInputNick:(NSString*)newNick
{
	int uid = sender.uid;
	IRCClient* u = [world findClientById:uid];
	if (!u) return;
	[u changeNick:newNick];
}

- (void)nickSheetWillClose:(NickSheet*)sender
{
	[nickSheet release];
	nickSheet = nil;
}

- (void)onChannelList:(id)sender
{
}

- (void)onAddServer:(id)sender
{
	IRCClient* u = world.selectedClient;
	IRCClientConfig* config = nil;
	if (u) {
		config = [[u.config mutableCopy] autorelease];
	}
	else {
		config = [[IRCClientConfig new] autorelease];
	}
	
	ServerDialog* d = [[ServerDialog new] autorelease];
	d.delegate = self;
	d.parentWindow = window;
	d.config = config;
	d.uid = -1;
	[serverDialogs addObject:d];
	[d start];
}

- (void)onCopyServer:(id)sender
{
	IRCClient* u = world.selectedClient;
	if (!u) return;
	
	IRCClientConfig* config = u.storedConfig;
	config.name = [config.name stringByAppendingString:@"_"];
	
	IRCClient* n = [world createClient:config reload:YES];
	[world expandClient:n];
	[world save];
}

- (void)onDeleteServer:(id)sender
{
	IRCClient* u = world.selectedClient;
	if (!u || u.isConnected) return;
	
	NSString* message = [NSString stringWithFormat:@"Delete %@ ?", u.name];
	
	NSInteger result = NSRunAlertPanel(message, @"", @"Delete", @"Cancel", nil);
	if (result != NSAlertDefaultReturn) return;
	
	[world destroyClient:u];
	[world save];
}

- (void)onServerProperties:(id)sender
{
	IRCClient* u = world.selectedClient;
	if (!u) return;
	
	if (u.propertyDialog) {
		[u.propertyDialog show];
		return;
	}
	
	ServerDialog* d = [[ServerDialog new] autorelease];
	d.delegate = self;
	d.parentWindow = window;
	d.config = u.storedConfig;
	d.uid = u.uid;
	[serverDialogs addObject:d];
	[d start];
}

- (void)serverDialogOnOK:(ServerDialog*)sender
{
	if (sender.uid < 0) {
		// create
		[world createClient:sender.config reload:YES];
	}
	else {
		// update
		IRCClient* u = [world findClientById:sender.uid];
		if (!u) return;
		[u updateConfig:sender.config];
	}
	[world save];
}

- (void)serverDialogWillClose:(ServerDialog*)sender
{
	[[sender retain] autorelease];
	[serverDialogs removeObjectIdenticalTo:sender];
	
	IRCClient* u = world.selectedClient;
	if (!u) return;
	u.propertyDialog = nil;
}

- (void)onServerAutoOp:(id)sender
{
}

- (void)onJoin:(id)sender
{
	IRCClient* u = world.selectedClient;
	IRCChannel* c = world.selectedChannel;
	if (!u || !c || !u.isLoggedIn || c.isActive || !c.isChannel) return;
	[u joinChannel:c];
}

- (void)onLeave:(id)sender
{
	IRCClient* u = world.selectedClient;
	IRCChannel* c = world.selectedChannel;
	if (!u || !c || !u.isLoggedIn || !c.isActive) return;
	if (c.isChannel) {
		[u partChannel:c];
	}
	else {
		[world destroyChannel:c];
	}
}

- (void)onTopic:(id)sender
{
}

- (void)onMode:(id)sender
{
	IRCClient* u = world.selectedClient;
	IRCChannel* c = world.selectedChannel;
	if (!u || !c) return;
	if (modeSheet) return;
	
	modeSheet = [ModeSheet new];
	modeSheet.delegate = self;
	modeSheet.window = window;
	modeSheet.uid = u.uid;
	modeSheet.cid = c.uid;
	modeSheet.mode = [[c.mode mutableCopy] autorelease];
	modeSheet.channelName = c.name;
	[modeSheet start];
}

- (void)modeSheetOnOK:(ModeSheet*)sender
{
	IRCClient* u = [world findClientById:sender.uid];
	IRCChannel* c = [world findChannelByClientId:sender.uid channelId:sender.cid];
	if (!u || !c) return;
	
	NSString* changeStr = [c.mode getChangeCommand:sender.mode];
	if (changeStr.length) {
		NSString* line = [NSString stringWithFormat:@"%@ %@ %@", MODE, c.name, changeStr];
		[u sendLine:line];
	}
	
	[modeSheet autorelease];
	modeSheet = nil;
}

- (void)modeSheetWillClose:(ModeSheet*)sender
{
	[modeSheet autorelease];
	modeSheet = nil;
}

- (void)onAddChannel:(id)sender
{
	IRCClient* u = world.selectedClient;
	IRCChannel* c = world.selectedChannel;
	if (!u) return;
	
	IRCChannelConfig* config;
	if (c && c.isChannel) {
		config = [[c.config mutableCopy] autorelease];
	}
	else {
		config = [[IRCChannelConfig new] autorelease];
	}
	config.name = @"";
	
	ChannelDialog* d = [[ChannelDialog new] autorelease];
	d.delegate = self;
	d.parentWindow = window;
	d.config = config;
	d.uid = u.uid;
	d.cid = -1;
	[channelDialogs addObject:d];
	[d start];
}

- (void)onDeleteChannel:(id)sender
{
	IRCChannel* c = world.selectedChannel;
	if (!c) return;
	[world destroyChannel:c];
	[world save];
}

- (void)onChannelProperties:(id)sender
{
	IRCClient* u = world.selectedClient;
	IRCChannel* c = world.selectedChannel;
	if (!u || !c) return;
	
	if (c.propertyDialog) {
		[c.propertyDialog show];
		return;
	}
	
	ChannelDialog* d = [[ChannelDialog new] autorelease];
	d.delegate = self;
	d.parentWindow = window;
	d.config = [[c.config mutableCopy] autorelease];
	d.uid = u.uid;
	d.cid = c.uid;
	[channelDialogs addObject:d];
	[d start];
}

- (void)channelDialogOnOK:(ChannelDialog*)sender
{
	if (sender.cid < 0) {
		// create
		IRCClient* u = [world findClientById:sender.uid];
		if (!u) return;
		[world createChannel:sender.config client:u reload:YES adjust:YES];
		[world expandClient:u];
		[world save];
	}
	else {
		// update
		IRCChannel* c = [world findChannelByClientId:sender.uid channelId:sender.cid];
		if (!c) return;
		[c updateConfig:sender.config];
	}
	
	[world save];
}

- (void)channelDialogWillClose:(ChannelDialog*)sender
{
	[[sender retain] autorelease];
	
	if (sender.cid >= 0) {
		IRCChannel* c = [world findChannelByClientId:sender.uid channelId:sender.cid];
		c.propertyDialog = nil;
	}
	
	[channelDialogs removeObjectIdenticalTo:sender];
}

- (void)onChannelAutoOp:(id)sender
{
}

- (void)whoisSelectedMembers:(id)sender deselect:(BOOL)deselect
{
	IRCClient* u = world.selectedClient;
	if (!u) return;
	
	for (IRCUser* m in [self selectedMembers:sender]) {
		[u sendWhois:m.nick];
	}
	
	if (deselect) {
		[self deselectMembers:sender];
	}
}

- (void)memberListDoubleClicked:(id)sender
{
	NSPoint pt = [window mouseLocationOutsideOfEventStream];
	pt = [sender convertPoint:pt fromView:nil];
	int n = [sender rowAtPoint:pt];
	if (n >= 0) {
		if ([[sender selectedRowIndexes] count] > 0) {
			[sender select:n];
		}
		[self whoisSelectedMembers:nil deselect:NO];
	}
}

- (void)onMemberWhois:(id)sender
{
	[self whoisSelectedMembers:sender deselect:YES];
}

- (void)onMemberTalk:(id)sender
{
	IRCClient* u = world.selectedClient;
	if (!u) return;
	
	for (IRCUser* m in [self selectedMembers:sender]) {
		IRCChannel* c = [u findChannel:m.nick];
		if (!c) {
			c = [world createTalk:m.nick client:u];
		}
		[world select:c];
	}
	
	[self deselectMembers:sender];
}

- (void)changeOp:(id)sender mode:(char)mode value:(BOOL)value
{
	IRCClient* u = world.selectedClient;
	IRCChannel* c = world.selectedChannel;
	if (!u || !u.isLoggedIn || !c || !c.isActive || !c.isChannel || !c.isOp) return;
	
	[u changeOp:c users:[self selectedMembers:sender] mode:mode value:value];
	[self deselectMembers:sender];
}

- (void)onMemberGiveOp:(id)sender
{
	[self changeOp:sender mode:'o' value:YES];
}

- (void)onMemberDeop:(id)sender
{
	[self changeOp:sender mode:'o' value:NO];
}

- (void)onMemberKick:(id)sender
{
	IRCClient* u = world.selectedClient;
	IRCChannel* c = world.selectedChannel;
	if (!u || !u.isLoggedIn || !c || !c.isActive || !c.isChannel || !c.isOp) return;
	
	for (IRCUser* m in [self selectedMembers:sender]) {
		[u kick:c target:m.nick];
	}
	
	[self deselectMembers:sender];
}

- (void)onMemberBan:(id)sender
{
}

- (void)onMemberKickBan:(id)sender
{
}

- (void)onMemberGiveVoice:(id)sender
{
	[self changeOp:sender mode:'v' value:YES];
}

- (void)onMemberDevoice:(id)sender
{
	[self changeOp:sender mode:'v' value:NO];
}

- (void)onMemberSendFile:(id)sender
{
}

- (void)onMemberPing:(id)sender
{
}

- (void)onMemberTime:(id)sender
{
}

- (void)onMemberVersion:(id)sender
{
}

- (void)onMemberUserInfo:(id)sender
{
}

- (void)onMemberClientInfo:(id)sender
{
}

- (void)onMemberAutoOp:(id)sender
{
}

- (void)onCopyUrl:(id)sender
{
	if (!pointedUrl) return;
	[[NSPasteboard generalPasteboard] setStringContent:pointedUrl];
	self.pointedUrl = nil;
}

- (void)onJoinChannel:(id)sender
{
	if (!pointedChannelName) return;
	IRCClient* u = world.selectedClient;
	if (!u || !u.isLoggedIn) return;
	[u send:JOIN, pointedChannelName, nil];
}

- (void)onCopyAddress:(id)sender
{
	if (!pointedAddress) return;
	[[NSPasteboard generalPasteboard] setStringContent:pointedAddress];
	self.pointedAddress = nil;
}

@end
