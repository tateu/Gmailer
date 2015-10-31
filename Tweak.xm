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
static NSMutableDictionary *gmailAccounts = nil;
static NSMutableDictionary *iOSMailAccounts = nil;
static PCSimpleTimer *updateTimer = nil;

static CPDistributedMessagingCenter *gmailerClient = nil;

static int loadGmailAccounts()
{
	NSDictionary *userInfo = [settings objectForKey:@"GmailAccounts"];
	if (!userInfo || userInfo.count == 0) {
		NSLog(@"[Gmailer] Error: Could not find Gmail application");
		return 1;
	}

	gmailAccounts = nil;
	gmailAccounts = [[NSMutableDictionary alloc] init];
	for (NSString *key in userInfo) {
		NSArray *addresses = [[userInfo objectForKey:key] componentsSeparatedByString:@","];
		NSMutableSet *addressSet = [NSMutableSet setWithCapacity:addresses.count];

		for (NSString *address in addresses) {
			[addressSet addObject:address];
		}

		[gmailAccounts setObject:addressSet forKey:key];
	}

	TweakLog(@"gmailerMessageNamed updateGmailAccounts\n%@", gmailAccounts);

	NSMutableDictionary *accounts = [[NSMutableDictionary alloc] init];
	NSMutableString *emailAddressesNotFound = [[NSMutableString alloc] init];
	NSMutableArray *trackedAccounts = [[NSMutableArray alloc] init];

	for (NSString *key in gmailAccounts) {
	    NSSet *addressSet = [gmailAccounts objectForKey:key];

		BOOL match = NO;
		for (MailAccount *account in [%c(MailAccount) activeAccounts]) {
			NSString *address = [account firstEmailAddress] ?: nil;
			if (!address) continue;

			if ([addressSet containsObject:address]) {
				[accounts setObject:address forKey:key];
				[trackedAccounts addObject:[NSString stringWithFormat:@"%@ -> %@", [addressSet anyObject], [account displayName]]];
				match = YES;
				break;
			}
		}

		if (!match) {
			if (emailAddressesNotFound.length) {
				[emailAddressesNotFound appendString:@"\n"];
			}

			[emailAddressesNotFound appendString:[addressSet anyObject]];
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
		NSMutableSet *emailAddresses = nil;
		NSString *emailAddress = nil;
		NSDictionary *APSMessageUserInfo = info[@"APSMessageUserInfo"];

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
			for (NSString *accountAddress in iOSMailAccounts) {
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

	if ([sender isEqualToString:@"Automatic"]) {
		BOOL alwaysFetchAll = settings[@"alwaysFetchAll"] ? [settings[@"alwaysFetchAll"] boolValue] : NO;
		NSMutableSet *accountsToFetch = [[NSMutableSet alloc] init];
		NSArray *emailAddresses = [userInfo[@"emailAddresses"] componentsSeparatedByString:@","];

		if (!alwaysFetchAll && emailAddresses && emailAddresses.count > 0) {
			for (NSString *emailAddress in emailAddresses) {
				MailAccount *account = [%c(MailAccount) accountContainingEmailAddress:emailAddress];

				if (account) {
					TweakLog(@"Fetch List %@", account);
					[accountsToFetch addObject:[[%c(MailboxSource) alloc] initWithMailbox:[account primaryMailboxUid]]];
				}
			}
		} else if (settings[@"iOSMailAccounts"]) {
			for (NSString *key in settings[@"iOSMailAccounts"]) {
				NSString *address = [settings[@"iOSMailAccounts"] objectForKey:key];
				MailAccount *account = [%c(MailAccount) accountContainingEmailAddress:address];
				if (account) {
					TweakLog(@"Fetch iOSMailAccounts %@", account);
					[accountsToFetch addObject:[[%c(MailboxSource) alloc] initWithMailbox:[account primaryMailboxUid]]];
				}
			}
		} else {
			for (MailAccount *account in [%c(MailAccount) activeAccounts]) {
				// if ([account isKindOfClass:%c(GmailAccount)]) {
					TweakLog(@"Fetch All %@", account);
					[accountsToFetch addObject:[[%c(MailboxSource) alloc] initWithMailbox:[account primaryMailboxUid]]];
				// }
			}
		}

		if (accountsToFetch.count > 0) {
			[autoFetchController fetchNow:126 withSources:accountsToFetch];
		}
	} else {
		MailAccount *account = [%c(MailAccount) accountWithUniqueId:sender];
		TweakLog(@"Fetch Preferences %@", account);
		MailboxSource *source = [[%c(MailboxSource) alloc] initWithMailbox:[account primaryMailboxUid]];
		[autoFetchController fetchNow:126 withSources:@[source]];
	}
}

-(BOOL)application:(id)arg1 didFinishLaunchingWithOptions:(id)arg2
{
	BOOL ret = %orig;

	TweakLog(@"didFinishLaunchingWithOptions");
	[self gmailerMessageNamed:@"fetchAccount" withUserInfo:@{@"sender" : @"Automatic"}];

	[[NSDistributedNotificationCenter defaultCenter] addObserverForName:@"net.tateu.gmailer/fetchAccount" object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *notification) {
		[self gmailerMessageNamed:@"fetchAccount" withUserInfo:@{@"sender" : @"Automatic", @"emailAddresses" : notification.userInfo[@"emailAddresses"] ?: @""}];
	}];

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

	SharedStorageManager *_sharedStorageManager = [%c(SharedStorageManager) sharedStorage];
	NSUserDefaults *userDefaults = _sharedStorageManager.userDefaults;
	NSArray *accountIds = [userDefaults objectForKey:@"kGmailSharedStorageSignedInAccountIds"];

	for (NSString *accountId in accountIds) {
		TweakLog(@"loadGmailAccount %@", accountId);
		NSString *accountKey = [@"kGmailSharedStorageAddresses_" stringByAppendingString:accountId];
		NSArray *accountAddresses = [userDefaults objectForKey:accountKey];
		NSMutableSet *addressSet = [NSMutableSet setWithCapacity:accountAddresses.count];

		for (NSArray *addressInfo in accountAddresses) {
			if (addressInfo.count == 2) {
				[addressSet addObject:addressInfo[1]];
			}
		}

		for (NSString *address in [self userEmailsForAccounts]) {
			if ([addressSet containsObject:address]) {
				// GoogleMailAccount *account = [self accountWithEmail:address];
				// NSInteger uniqueId = account.accountId;
				NSInteger uniqueId = [self fetchOrAssignUniqueIdForEmail:address];
				// NSData *data = [NSKeyedArchiver archivedDataWithRootObject:addressSet];
				[accountMap setObject:[[addressSet allObjects] componentsJoinedByString:@","] forKey:[NSString stringWithFormat:@"%ld", (long)uniqueId]];
				break;
			}
		}
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
