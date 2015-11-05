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

#define kCFCoreFoundationVersionNumber_iOS_9 1240.10

#define plistfile @"/var/mobile/Library/Preferences/net.tateu.gmailer.plist"
#define PreferencesChangedNotification "net.tateu.gmailer/preferences"
static BOOL enabled = YES;
static BOOL blockGmail = NO;
static NSMutableDictionary *settings = nil;
static NSMutableDictionary *iOSMailAccounts = nil;
static PCSimpleTimer *updateTimer = nil;
static BBDataProviderManager *dataProviderManager = nil;

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
// %hook BBServer
// - (void)_publishBulletinRequest:(BBBulletinRequest *)bulletin forSectionID:(id)arg2 forDestinations:(unsigned int)arg3 alwaysToLockScreen:(BOOL)arg4
// {
// 	if (enabled && blockGmail && [bulletin.sectionID isEqualToString:@"com.google.Gmail"]) {
// 		TweakLog(@"_publishBulletinRequest gmail\n%@\n%@\n%@", bulletin.title, bulletin.subtitle, bulletin.message);
// 		// return;
// 	}
//
// 	%orig;
// }
// %end

%hook SBApplication
-(void)setBadge:(id)badge
{
	if (enabled && blockGmail && [self.bundleIdentifier isEqualToString:@"com.google.Gmail"]) {
		TweakLog(@"setBadge %@", self.bundleIdentifier);
		badge = @(0);
	}

	%orig(badge);
}
%end

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

	[[NSDistributedNotificationCenter defaultCenter] postNotificationName:@"net.tateu.gmailer/fetchAccount" object:nil userInfo:@{@"sender" : @"Automatic", @"data" : [[timer.userInfo[@"emailAddresses"] allObjects] componentsJoinedByString:@","]}];

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

	if (!enabled) {
		return %orig;
	}

	if (info[@"APSMessageTopic"] && [info[@"APSMessageTopic"] isEqualToString:@"com.google.Gmail"]) {
		if (iOSMailAccounts.count > 0) {
			NSDictionary *APSMessageUserInfo = info[@"APSMessageUserInfo"];
			if (settings[@"newEmailOnly"] && [settings[@"newEmailOnly"] boolValue] && (!APSMessageUserInfo[@"aps"] || !APSMessageUserInfo[@"aps"][@"alert"])) {
				if (blockGmail) {
					return nil;
				} else {
					return %orig;
				}
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

		if (blockGmail) {
			return nil;
		}
	}

	TweakLog(@"SpringBoard initWithDictionary xpcMessage\n%@", info);

 	return %orig;
}
%end //hook APSIncomingMessage
%end //group SpringBoardGroup

%group SpringBoardGroup_iOS9
%hook UNDefaultDataProvider
-(void)noteSectionInfoDidChange:(BBSectionInfo *)sectionInfo
{
	%orig;

	if (enabled && blockGmail && dataProviderManager && [self.sectionIdentifier isEqualToString:@"com.google.Gmail"]) {
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.1 * NSEC_PER_SEC), dispatch_get_main_queue(), ^(void) {
			BBRemoteDataProvider *remoteDataProvider = [dataProviderManager dataProviderForSectionID:@"com.google.Gmail"];
			TweakLog(@"UNDefaultDataProvider noteSectionInfoDidChange\n%@", remoteDataProvider);
			if (remoteDataProvider) {
				BBSectionInfo *sectionInfo = remoteDataProvider.defaultSectionInfo;
				if (sectionInfo) {
					TweakLog(@"UNDefaultDataProvider noteSectionInfoDidChange 1\n%@", sectionInfo);
					sectionInfo.allowsNotifications = YES;
					sectionInfo.showsInLockScreen = YES;
					sectionInfo.showsInNotificationCenter = YES;
					sectionInfo.pushSettings = 63; //49 is 110 001 in reverse-reverse == [s:B--] [e:-SA] -- [s:BSA] [e:BSA]
					sectionInfo.alertType = 1; //Banner
					TweakLog(@"UNDefaultDataProvider noteSectionInfoDidChange 2\n%@", sectionInfo);
					[remoteDataProvider setSectionInfo:sectionInfo];
				}
			}
		});
	}

	// %orig(sectionInfo);
}
%end

%hook BBDataProviderManager
- (void)loadAllDataProvidersAndPerformMigration:(BOOL)arg1
{
	%orig;

	dataProviderManager = self;

	if (enabled && blockGmail) {
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^(void) {
			BBRemoteDataProvider *remoteDataProvider = [self dataProviderForSectionID:@"com.google.Gmail"];
			TweakLog(@"BBDataProviderManager\n%@", remoteDataProvider);
			if (remoteDataProvider) {
				BBSectionInfo *sectionInfo = remoteDataProvider.defaultSectionInfo;
				if (sectionInfo) {
					TweakLog(@"BBDataProviderManager loadAllDataProviders 1\n%@", sectionInfo);
					sectionInfo.allowsNotifications = YES;
					sectionInfo.showsInLockScreen = YES;
					sectionInfo.showsInNotificationCenter = YES;
					sectionInfo.pushSettings = 63; //49 is 110 001 in reverse-reverse == [s:B--] [e:-SA] -- [s:BSA] [e:BSA]
					sectionInfo.alertType = 1; //Banner
					TweakLog(@"BBDataProviderManager loadAllDataProviders 2\n%@", sectionInfo);
					[remoteDataProvider setSectionInfo:sectionInfo];
				}
			}
		});
	}
}
%end
%end //group SpringBoardGroup_iOS9

%group SpringBoardGroup_iOS8
%hook RLNDataProvider
-(void)noteSectionInfoDidChange:(BBSectionInfo *)sectionInfo
{
	%orig;

	if (enabled && blockGmail && dataProviderManager && [self.sectionIdentifier isEqualToString:@"com.google.Gmail"]) {
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.1 * NSEC_PER_SEC), dispatch_get_main_queue(), ^(void) {
			BBRemoteDataProvider *remoteDataProvider = [dataProviderManager dataProviderForSectionID:@"com.google.Gmail"];
			TweakLog(@"RLNDataProvider noteSectionInfoDidChange\n%@", remoteDataProvider);
			if (remoteDataProvider) {
				BBSectionInfo *sectionInfo = remoteDataProvider.defaultSectionInfo;
				if (sectionInfo) {
					TweakLog(@"RLNDataProvider noteSectionInfoDidChange 1\n%@", sectionInfo);
					sectionInfo.allowsNotifications = YES;
					sectionInfo.showsInLockScreen = YES;
					sectionInfo.showsInNotificationCenter = YES;
					sectionInfo.pushSettings = 63; //49 is 110 001 in reverse-reverse == [s:B--] [e:-SA] -- [s:BSA] [e:BSA]
					sectionInfo.alertType = 1; //Banner
					TweakLog(@"RLNDataProvider noteSectionInfoDidChange 2\n%@", sectionInfo);
					[remoteDataProvider setSectionInfo:sectionInfo];
				}
			}
		});
	}

	// %orig(sectionInfo);
}
%end

%hook BBDataProviderManager
- (void)loadAllDataProviders
{
	%orig;

	dataProviderManager = self;

	if (enabled && blockGmail) {
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^(void) {
			BBRemoteDataProvider *remoteDataProvider = [self dataProviderForSectionID:@"com.google.Gmail"];
			TweakLog(@"BBDataProviderManager\n%@", remoteDataProvider);
			if (remoteDataProvider) {
				BBSectionInfo *sectionInfo = remoteDataProvider.defaultSectionInfo;
				if (sectionInfo) {
					TweakLog(@"BBDataProviderManager loadAllDataProviders 1\n%@", sectionInfo);
					sectionInfo.allowsNotifications = YES;
					sectionInfo.showsInLockScreen = YES;
					sectionInfo.showsInNotificationCenter = YES;
					sectionInfo.pushSettings = 63; //49 is 110 001 in reverse-reverse == [s:B--] [e:-SA] -- [s:BSA] [e:BSA]
					sectionInfo.alertType = 1; //Banner
					TweakLog(@"BBDataProviderManager loadAllDataProviders 2\n%@", sectionInfo);
					[remoteDataProvider setSectionInfo:sectionInfo];
				}
			}
		});
	}
}
%end
%end //group SpringBoardGroup_iOS8

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
		if (userInfo[@"data"] && userInfo[@"data"] != (id)[NSNull null]) {
			emailAddresses = [userInfo[@"data"] componentsSeparatedByString:@","];
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
				TweakLog(@"Fetch All %@", account);
				if (inboxOnly) {
					[accountsToFetch addObject:[[%c(MailboxSource) alloc] initWithMailbox:[account primaryMailboxUid]]];
				} else {
					[accountsToFetch addObject:account];
				}
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
		MailAccount *account = nil;

		if ([sender isEqualToString:@"uniqueId"]) {
			account = [%c(MailAccount) accountWithUniqueId:userInfo[@"data"]];
		} else if ([sender isEqualToString:@"firstEmailAddress"]) {
			account = [%c(MailAccount) accountContainingEmailAddress:userInfo[@"data"]];
		} else if ([sender isEqualToString:@"URLString"]) {
			account = [%c(MailAccount) accountWithURLString:userInfo[@"data"]];
		}

		TweakLog(@"Fetch Preferences\n%@\n%@", account, userInfo);
		if (inboxOnly && account) {
			MailboxSource *source = [[%c(MailboxSource) alloc] initWithMailbox:[account primaryMailboxUid]];
			[autoFetchController fetchNow:125 withSources:@[source]];
		} else if (account) {
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
			[self gmailerMessageNamed:@"fetchAccount" withUserInfo:@{@"sender" : (notification.userInfo[@"sender"] ?: @"Automatic"), @"data" : (notification.userInfo[@"data"] ?: [NSNull null])}];
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

	enabled = settings[@"enabled"] ? [settings[@"enabled"] boolValue] : YES;
	blockGmail = settings[@"blockGmail"] ? [settings[@"blockGmail"] boolValue] : NO;

	if (%c(SpringBoard) && enabled && blockGmail) {
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.1 * NSEC_PER_SEC), dispatch_get_main_queue(), ^(void) {
			if (dataProviderManager) {
				BBRemoteDataProvider *remoteDataProvider = [dataProviderManager dataProviderForSectionID:@"com.google.Gmail"];
				TweakLog(@"LoadSettings\n%@", remoteDataProvider);
				if (remoteDataProvider) {
					BBSectionInfo *sectionInfo = remoteDataProvider.defaultSectionInfo;
					if (sectionInfo) {
						TweakLog(@"LoadSettings 1\n%@", sectionInfo);
						sectionInfo.allowsNotifications = YES;
						sectionInfo.showsInLockScreen = YES;
						sectionInfo.showsInNotificationCenter = YES;
						sectionInfo.pushSettings = 63; //49 is 110 001 in reverse-reverse == [s:B--] [e:-SA] -- [s:BSA] [e:BSA]
						sectionInfo.alertType = 1; //Banner
						TweakLog(@"LoadSettings 2\n%@", sectionInfo);
						[remoteDataProvider setSectionInfo:sectionInfo];
					}
				}
			}
		});

		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^(void) {
			SBApplication *app = [[%c(SBApplicationController) sharedInstance] applicationWithBundleIdentifier:@"com.google.Gmail"];
			if (app) {
				[app setBadge:@(0)];
			}
		});
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
			if (kCFCoreFoundationVersionNumber < kCFCoreFoundationVersionNumber_iOS_9) {
				%init(SpringBoardGroup_iOS8);
			} else {
				%init(SpringBoardGroup_iOS9);
			}

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
