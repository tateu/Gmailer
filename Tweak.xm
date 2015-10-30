#import <Foundation/NSDistributedNotificationCenter.h>
#import "headers.h"

#define DEBUG
#ifdef DEBUG
#define TweakLog(fmt, ...) NSLog((@"[Gmailer] [Line %d]: "  fmt), __LINE__, ##__VA_ARGS__)
#else
#define TweakLog(fmt, ...)
// #define NSLog(fmt, ...)
#endif

#define plistfile @"/var/mobile/Library/Preferences/net.tateu.gmailer.plist"
#define PreferencesChangedNotification "net.tateu.gmailer/preferences"
static NSMutableDictionary *settings = nil;
static NSArray *sharedGmailAccounts = nil;
static NSMutableArray *iOSGmailAccounts = nil;
static PCSimpleTimer *updateTimer = nil;

static int loadGmailAccounts()
{
	LSApplicationProxy *gmailApp = [%c(LSApplicationProxy) applicationProxyForIdentifier:@"com.google.Gmail"];
	if (!gmailApp) {
		NSLog(@"[Gmailer] Error: Could not find Gmail application");
		return 1;
	}

	NSURL *containerURL = [gmailApp.groupContainerURLs objectForKey:@"group.com.google.Gmail"];
	if (!containerURL) {
		NSLog(@"[Gmailer] Error: Could not find Gmail groupContainerURLs");
		return 2;
	}

	NSUserDefaults *userDefaults = [[%c(NSUserDefaults) alloc] _initWithSuiteName:@"group.com.google.Gmail" container:containerURL];
	NSArray *accountIds = [userDefaults objectForKey:@"kGmailSharedStorageSignedInAccountIds"];

	if (!accountIds || accountIds.count == 0) {
		NSLog(@"[Gmailer] Error: Could not find Gmail kGmailSharedStorageSignedInAccountIds");
		return 3;
	}

	// ***from gmailpushenabler by Leonard Hecker (https://gist.github.com/lhecker/00850043b35cf207cafc)
	iOSGmailAccounts = [[NSMutableArray alloc] init];
	NSMutableString *emailAddressesNotFound = [[NSMutableString alloc] init];
	NSMutableArray *trackedAccounts = [[NSMutableArray alloc] init];

	NSMutableArray *accounts = [NSMutableArray arrayWithCapacity:accountIds.count];

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

		BOOL match = NO;
		for (MailAccount *account in [%c(MailAccount) activeAccounts]) {
			NSString *address = [account firstEmailAddress] ?: nil;
			if (!address) continue;

			if ([addressSet containsObject:address]) {
				[iOSGmailAccounts addObject:address];
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

		[accounts addObject:addressSet];
	}

	sharedGmailAccounts = [accounts copy];
	// ***

	if (iOSGmailAccounts.count == 0) {
		NSLog(@"[Gmailer] Error: Could not find iOS Gmail accounts");
		return 4;
	}

	[settings setObject:trackedAccounts forKey:@"trackedAccounts"];

	if (emailAddressesNotFound.length) {
		NSLog(@"[Gmailer] Warning: Some of your Gmail accounts do not have corresponding iOS accounts with the same email address");
		[settings setObject:emailAddressesNotFound forKey:@"message"];
		return 5;
	}

	TweakLog(@"loadGmailAccounts\n%@\n%@", iOSGmailAccounts, sharedGmailAccounts);

	return 0;
}

%group SpringBoardGroup
%hook SpringBoard
-(void)applicationDidFinishLaunching:(id)application
{
	%orig;

	dispatch_async(dispatch_get_main_queue(), ^{
		[settings removeObjectForKey:@"trackedAccounts"];
		[settings removeObjectForKey:@"message"];
		int result = loadGmailAccounts();
		[settings setObject:@(result) forKey:@"result"];
		[settings setObject:iOSGmailAccounts forKey:@"iOSGmailAccounts"];
		[settings writeToFile:plistfile atomically:YES];
	});
}
%end

%hook APSIncomingMessage
%new
- (void)GAUpdateTimerFired:(PCSimpleTimer *)timer
{
	TweakLog(@"Fetch GAUpdateTimerFired\n%@", timer.userInfo[@"emailAddresses"]);

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

	if (iOSGmailAccounts.count > 0 && info[@"APSMessageTopic"] && [info[@"APSMessageTopic"] isEqualToString:@"com.google.Gmail"]) {
		NSMutableSet *emailAddresses = nil;
		NSString *emailAddress = nil;
		NSDictionary *APSMessageUserInfo = info[@"APSMessageUserInfo"];

		if (APSMessageUserInfo[@"a"]) {
			NSInteger index = [APSMessageUserInfo[@"a"] intValue];

			// ***from gmailpushenabler by Leonard Hecker (https://gist.github.com/lhecker/00850043b35cf207cafc)
			if (index >= 1 && index <= sharedGmailAccounts.count) {
				NSSet *addressSet = sharedGmailAccounts[index - 1];

				for (NSString *address in iOSGmailAccounts) {
					if ([addressSet containsObject:address]) {
						emailAddress = address;
						break;
					}
				}
			}
			// ***
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
		}

		updateTimer = [[%c(PCSimpleTimer) alloc] initWithFireDate:fireDate serviceIdentifier:@"net.tateu.gmailer" target:self selector:@selector(GAUpdateTimerFired:) userInfo:@{@"fireDate" : fireDate, @"emailAddresses" : emailAddresses}];
		[updateTimer scheduleInRunLoop:[NSRunLoop mainRunLoop]];

		TweakLog(@"xpcMessage (%@)\n%@", APSMessageUserInfo[@"a"], updateTimer.userInfo);
	}

 	return %orig;
}
%end //hook APSIncomingMessage
%end //group SpringBoardGroup

// %group MailGroup
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
// %end //group MailGroup

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
				// %init(MailGroup);
				CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, SettingsChanged, CFSTR(PreferencesChangedNotification), NULL, CFNotificationSuspensionBehaviorCoalesce);

				[[NSDistributedNotificationCenter defaultCenter] addObserverForName:@"net.tateu.gmailer/fetchAccount" object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *notification) {
					NSString *sender = notification.userInfo[@"sender"];
					AutoFetchController *autoFetchController = [objc_getClass("AutoFetchController") sharedController];

					if ([sender isEqualToString:@"Automatic"]) {
						BOOL alwaysFetchAll = settings[@"alwaysFetchAll"] ? [settings[@"alwaysFetchAll"] boolValue] : NO;
						NSMutableSet *accountsToFetch = [[NSMutableSet alloc] init];
						NSArray *emailAddresses = [notification.userInfo[@"emailAddresses"] componentsSeparatedByString:@","];

						if (!alwaysFetchAll && emailAddresses && emailAddresses.count > 0) {
							for (NSString *emailAddress in emailAddresses) {
								MailAccount *account = [%c(MailAccount) accountContainingEmailAddress:emailAddress];

								if (account) {
									TweakLog(@"Fetch List %@", account);
									[accountsToFetch addObject:[[%c(MailboxSource) alloc] initWithMailbox:[account primaryMailboxUid]]];
								}
							}
						} else if (settings[@"iOSGmailAccounts"]) {
							for (MailAccount *address in settings[@"iOSGmailAccounts"]) {
								MailAccount *account = [%c(MailAccount) accountContainingEmailAddress:address];
								if (account) {
									TweakLog(@"Fetch iOSGmailAccounts %@", account);
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
				}];
			}
		}
	}
}
