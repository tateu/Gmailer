#import <Foundation/NSDistributedNotificationCenter.h>
#import <AppSupport/CPDistributedMessagingCenter.h>
#import <rocketbootstrap.h>
#import "headers.h"

// #define DEBUG
#ifdef DEBUG
#define TweakLog(fmt, ...) NSLog((@"[Gmailer] [Line %d]: "  fmt), __LINE__, ##__VA_ARGS__)
#else
#define TweakLog(fmt, ...)
// #define NSLog(fmt, ...)
#endif

#define plistfile @"/var/mobile/Library/Preferences/net.tateu.gmailer.plist"
#define PreferencesChangedNotification "net.tateu.gmailer/preferences"
static NSMutableDictionary *settings = nil;
static NSMutableDictionary *iOSMailAccounts = nil;
static PCSimpleTimer *updateTimer = nil;

static CPDistributedMessagingCenter *gmailerClient = nil;

static int loadGmailAccounts()
{
	NSDictionary *gmailAccounts = [settings objectForKey:@"GmailAccounts"];
	if (!gmailAccounts || gmailAccounts.count == 0) {
		NSLog(@"[Gmailer] Error: Could not find Gmail application");
		return 1;
	}

	TweakLog(@"gmailerMessageNamed updateGmailAccounts\n%@", gmailAccounts);

	NSMutableDictionary *accounts = [[NSMutableDictionary alloc] init];
	NSMutableString *emailAddressesNotFound = [[NSMutableString alloc] init];
	NSMutableArray *trackedAccounts = [[NSMutableArray alloc] init];

	for (NSString *key in gmailAccounts) {
	    NSString *gmailAddress = [gmailAccounts objectForKey:key];

		BOOL match = NO;
		for (MailAccount *account in [%c(MailAccount) activeAccounts]) {
			NSString *address = [account firstEmailAddress] ?: nil;
			if (!address) continue;

			NSString *username = [account username];
			TweakLog(@"gmailerMessageNamed updateGmailAccounts %@ - %@ - %@", gmailAddress, username, address);

			if ((username && [gmailAddress isEqualToString:username]) || ([gmailAddress isEqualToString:address])) {
				[accounts setObject:address forKey:key];
				[trackedAccounts addObject:[NSString stringWithFormat:@"%@ -> %@", gmailAddress, [account displayName]]];
				match = YES;
				break;
			}
		}

		if (!match) {
			if (emailAddressesNotFound.length) {
				[emailAddressesNotFound appendString:@"\n"];
			}

			[emailAddressesNotFound appendString:gmailAddress];
		}
	}

	iOSMailAccounts = [accounts copy];

	if (iOSMailAccounts.count == 0) {
		NSLog(@"[Gmailer] Error: Could not find iOS Gmail accounts");
		return 4;
	}

	[settings setObject:trackedAccounts forKey:@"trackedAccounts"];

	if (emailAddressesNotFound.length) {
		NSLog(@"[Gmailer] Warning: Some of your Gmail accounts do not have corresponding iOS accounts with the same email address");
		[settings setObject:emailAddressesNotFound forKey:@"message"];
		return 5;
	}

	TweakLog(@"loadGmailAccounts\n%@\n%@", iOSMailAccounts, trackedAccounts);

	return 0;
}

%group SpringBoardGroup
%hook SpringBoard
%new
- (void)gmailerMessageNamed:(NSString *)name withUserInfo:(NSDictionary *)userInfo
{
	if ([name isEqualToString:@"updateGmailAccounts"] || [name isEqualToString:@"relinkEmailAccounts"]) {
		[settings removeObjectForKey:@"trackedAccounts"];
		[settings removeObjectForKey:@"message"];

		if ([name isEqualToString:@"updateGmailAccounts"]) {
			[settings setObject:userInfo forKey:@"GmailAccounts"];
			TweakLog(@"gmailerMessageNamed updateGmailAccounts\n%@", userInfo);
		}

		int result = loadGmailAccounts();
		if (!iOSMailAccounts) {
			iOSMailAccounts = [[NSMutableDictionary alloc] init];
		}

		[settings setObject:@(result) forKey:@"result"];
		[settings setObject:iOSMailAccounts forKey:@"iOSMailAccounts"];
		[settings writeToFile:plistfile atomically:YES];
	}
}

-(void)applicationDidFinishLaunching:(id)application
{
	%orig;

	dispatch_async(dispatch_get_main_queue(), ^{
		[self gmailerMessageNamed:@"relinkEmailAccounts" withUserInfo:nil];

		[[NSDistributedNotificationCenter defaultCenter] addObserverForName:@"net.tateu.gmailer/relinkEmailAccounts" object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *notification) {
			[self gmailerMessageNamed:@"relinkEmailAccounts" withUserInfo:nil];
		}];

		CPDistributedMessagingCenter *c = [CPDistributedMessagingCenter centerNamed:@"net.tateu.gmailer"];
		rocketbootstrap_distributedmessagingcenter_apply(c);
		[c runServerOnCurrentThread];
		[c registerForMessageName:@"updateGmailAccounts" target:self selector:@selector(gmailerMessageNamed:withUserInfo:)];
	});
}
%end

%hook APSIncomingMessage
%new
- (void)GAUpdateTimerFired:(PCSimpleTimer *)timer
{
	TweakLog(@"Fetch GAUpdateTimerFired\n%@", timer.userInfo[@"emailAddresses"]);

	// Should we ping the Mail app to wake it up?
	// BOOL ret = [[%c(SBBackgroundMultitaskingManager) sharedInstance] _launchAppForUpdating:@"com.apple.mobilemail" trigger:1 pushNotificationUserInfo:nil withWatchdoggableCompletion:nil];

	[[NSDistributedNotificationCenter defaultCenter] postNotificationName:@"net.tateu.gmailer/fetchAccount" object:nil userInfo:@{@"sender" : @"Automatic", @"emailAddresses" : [[timer.userInfo[@"emailAddresses"] allObjects] componentsJoinedByString:@","]}];

	[updateTimer invalidate];
	updateTimer = nil;
}

-(id)initWithDictionary:(id)info xpcMessage:(id)arg2
{
	// TweakLog(@"SpringBoard initWithDictionary xpcMessage\n%@", info);

	// Oct 23 22:32:50 Someones-iPhone-6s SpringBoard[2859]: [Gmailer] [Line 114]: SpringBoard initWithDictionary xpcMessage
	// {
	//     APSIncomingMessageFromStorage = 0;
	//     APSIncomingMessageLastMessageFromStorage = 0;
	//     APSIncomingMessageTimestamp = "1971-06-03 05:45:55 +0000";
	//     APSMessageGUID = "992BE740-427E-469F-BC87-17D9BF8F7431";
	//     APSMessageIdentifier = 13669603;
	//     APSMessageTopic = "com.google.Gmail";
	//     APSMessageUserInfo =     {
	//         a = 1;
	//         aps =         {
	//             badge = 2;
	//         };
	//         ds = 3;
	//     };
	//     APSProtocolMessagePriority = 10;
	// }

	if (settings[@"enabled"] && ![settings[@"enabled"] boolValue]) {
		return %orig;
	}

	if (iOSMailAccounts.count > 0 && info[@"APSMessageTopic"] && [info[@"APSMessageTopic"] isEqualToString:@"com.google.Gmail"]) {
		TweakLog(@"SpringBoard initWithDictionary xpcMessage\n%@", info);
		NSDictionary *APSMessageUserInfo = info[@"APSMessageUserInfo"];
		if (settings[@"newEmailOnly"] && [settings[@"newEmailOnly"] boolValue] && (!APSMessageUserInfo[@"aps"] || !APSMessageUserInfo[@"aps"][@"alert"])) {
			return %orig;
		}

		NSMutableSet *emailAddresses = nil;
		NSString *emailAddress = nil;

		if (APSMessageUserInfo[@"a"]) {
			emailAddress = [iOSMailAccounts objectForKey:APSMessageUserInfo[@"a"]];
		}

		NSDate *fireDate = [NSDate dateWithTimeIntervalSinceNow:10];
		if (updateTimer) {
			emailAddresses = updateTimer.userInfo[@"emailAddresses"];
			fireDate = updateTimer.userInfo[@"fireDate"];
			[updateTimer invalidate];
			updateTimer = nil;
		} else {
			emailAddresses = [[NSMutableSet alloc] init];
		}

		if (emailAddress) {
			[emailAddresses addObject:emailAddress];
		} else {
			for (NSString *accountAddress in [iOSMailAccounts allValues]) {
				[emailAddresses addObject:accountAddress];
			}
		}

		updateTimer = [[%c(PCSimpleTimer) alloc] initWithFireDate:fireDate serviceIdentifier:@"net.tateu.gmailer" target:self selector:@selector(GAUpdateTimerFired:) userInfo:@{@"fireDate" : fireDate, @"emailAddresses" : emailAddresses}];
		[updateTimer scheduleInRunLoop:[NSRunLoop mainRunLoop]];

		TweakLog(@"xpcMessage (%@)\n%@", APSMessageUserInfo[@"a"], updateTimer.userInfo);
	}

 	return %orig;
}
%end //hook APSIncomingMessage
%end //group SpringBoardGroup

%group MailGroup
%hook MailAppController
%new
- (void)gmailerMessageNamed:(NSString *)name withUserInfo:(NSDictionary *)userInfo
{
	NSString *sender = userInfo[@"sender"];
	AutoFetchController *autoFetchController = [%c(AutoFetchController) sharedController];
	BOOL inboxOnly = settings[@"inboxOnly"] ? [settings[@"inboxOnly"] boolValue] : YES;

	if ([sender isEqualToString:@"Automatic"]) {
		BOOL alwaysFetchAll = settings[@"alwaysFetchAll"] ? [settings[@"alwaysFetchAll"] boolValue] : NO;
		NSMutableArray *accountsToFetch = [[NSMutableArray alloc] init];
		NSArray *emailAddresses = nil;
		if (userInfo[@"emailAddresses"] && userInfo[@"emailAddresses"] != (id)[NSNull null]) {
			emailAddresses = [userInfo[@"emailAddresses"] componentsSeparatedByString:@","];
		}
		TweakLog(@"gmailerMessageNamed Automatic\n%@", emailAddresses);

		if (!alwaysFetchAll && emailAddresses && emailAddresses.count > 0) {
			for (NSString *emailAddress in emailAddresses) {
				MailAccount *account = [%c(MailAccount) accountContainingEmailAddress:emailAddress];

				if (account) {
					TweakLog(@"Fetch List %@", account);
					if (inboxOnly) {
						[accountsToFetch addObject:[[%c(MailboxSource) alloc] initWithMailbox:[account primaryMailboxUid]]];
					} else {
						[accountsToFetch addObject:account];
					}
				}
			}
		} else if (settings[@"iOSMailAccounts"]) {
			for (NSString *address in [settings[@"iOSMailAccounts"] allValues]) {
				MailAccount *account = [%c(MailAccount) accountContainingEmailAddress:address];
				if (account) {
					TweakLog(@"Fetch iOSMailAccounts %@", account);
					if (inboxOnly) {
						[accountsToFetch addObject:[[%c(MailboxSource) alloc] initWithMailbox:[account primaryMailboxUid]]];
					} else {
						[accountsToFetch addObject:account];
					}
				}
			}
		} else {
			for (MailAccount *account in [%c(MailAccount) activeAccounts]) {
				// if ([account isKindOfClass:%c(GmailAccount)]) {
					TweakLog(@"Fetch All %@", account);
					if (inboxOnly) {
						[accountsToFetch addObject:[[%c(MailboxSource) alloc] initWithMailbox:[account primaryMailboxUid]]];
					} else {
						[accountsToFetch addObject:account];
					}
				// }
			}
		}

		if (accountsToFetch.count > 0) {
			if (inboxOnly) {
				[autoFetchController fetchNow:125 withSources:accountsToFetch];
			} else {
				[autoFetchController fetchNow:125 withAccounts:accountsToFetch];
			}
		}
	} else {
		MailAccount *account = [%c(MailAccount) accountWithUniqueId:sender];
		TweakLog(@"Fetch Preferences %@", account);
		if (inboxOnly) {
			MailboxSource *source = [[%c(MailboxSource) alloc] initWithMailbox:[account primaryMailboxUid]];
			[autoFetchController fetchNow:125 withSources:@[source]];
		} else {
			[autoFetchController fetchNow:125 withAccounts:@[account]];
		}
	}
}

-(BOOL)application:(id)arg1 didFinishLaunchingWithOptions:(id)arg2
{
	BOOL ret = %orig;

	TweakLog(@"didFinishLaunchingWithOptions");
	static dispatch_once_t mailAppToken = 0;
	dispatch_once(&mailAppToken, ^{
		[self gmailerMessageNamed:@"fetchAccount" withUserInfo:@{@"sender" : @"Automatic"}];

		[[NSDistributedNotificationCenter defaultCenter] addObserverForName:@"net.tateu.gmailer/fetchAccount" object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *notification) {
			[self gmailerMessageNamed:@"fetchAccount" withUserInfo:@{@"sender" : (notification.userInfo[@"sender"] ?: @"Automatic"), @"emailAddresses" : (notification.userInfo[@"emailAddresses"] ?: [NSNull null])}];
		}];
	});

	return ret;
}
%end

// %hook AutoFetchController
// - (void)fetchNow:(NSInteger)arg1
// {
// 	%orig;
// 	TweakLog(@"AutoFetchController fetchNow (%d)", (int)arg1);
// }
// - (void)fetchNow:(NSInteger)arg1 withAccounts:(id)arg2
// {
// 	%orig;
// 	TweakLog(@"AutoFetchController withAccounts (%d)\n%@", (int)arg1, arg2);
// }
// - (void)fetchNow:(NSInteger)arg1 withSources:(id)arg2
// {
// 	%orig;
// 	TweakLog(@"AutoFetchController withSources (%d)\n%@", (int)arg1, arg2);
// }
// %end //hook AutoFetchController
%end //group MailGroup

%group GmailGroup
%hook GmailAccountManager
- (void)application:(id)arg1 didFinishLaunchingWithOptions:(id)arg2
{
	%orig;
	TweakLog(@"GmailAccountManager didFinishLaunchingWithOptions");
	gmailerClient = [%c(CPDistributedMessagingCenter) centerNamed:@"net.tateu.gmailer"];
	rocketbootstrap_distributedmessagingcenter_apply(gmailerClient);
}

- (void)updateAccounts
{
	%orig;

	NSMutableDictionary *accountMap = [[NSMutableDictionary alloc] init];
	for (NSString *address in [self userEmailsForAccounts]) {
		NSInteger uniqueId = [self fetchOrAssignUniqueIdForEmail:address];
		[accountMap setObject:address forKey:[NSString stringWithFormat:@"%ld", (long)uniqueId]];
	}

	[gmailerClient sendMessageName:@"updateGmailAccounts" userInfo:accountMap];
	TweakLog(@"GmailAccountManager updateAccounts\n%@", accountMap);
}
%end // hook GmailAccountManager
%end // group GmailGroup

static void LoadSettings()
{
	settings = [NSMutableDictionary dictionaryWithContentsOfFile:plistfile];
	if (settings == nil) {
		settings = [[NSMutableDictionary alloc] init];
	}
}

static void SettingsChanged(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo)
{
	LoadSettings();
}

%ctor
{
	@autoreleasepool {
		if (%c(SpringBoard)) {
			LoadSettings();
			%init(SpringBoardGroup);
			CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, SettingsChanged, CFSTR(PreferencesChangedNotification), NULL, CFNotificationSuspensionBehaviorCoalesce);
		} else {
			NSString *bundleIdentifier = [NSBundle mainBundle].bundleIdentifier;

			if ([bundleIdentifier isEqualToString:@"com.apple.mobilemail"]) {
				LoadSettings();
				%init(MailGroup);
				CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, SettingsChanged, CFSTR(PreferencesChangedNotification), NULL, CFNotificationSuspensionBehaviorCoalesce);
			} else if ([bundleIdentifier isEqualToString:@"com.google.Gmail"]) {
				%init(GmailGroup);
			}
		}
	}
}
