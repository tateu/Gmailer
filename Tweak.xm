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
static NSArray *sharedGmailAccounts = nil;
static NSArray *iOSGmailAccounts = nil;
static PCSimpleTimer *updateTimer = nil;

static int loadGmailAccounts()
{
	LSApplicationProxy *gmailApp = [%c(LSApplicationProxy) applicationProxyForIdentifier:@"com.google.Gmail"];
	if (!gmailApp) {
		return 1;
	}

	NSURL *containerURL = [gmailApp.groupContainerURLs objectForKey:@"group.com.google.Gmail"];
	if (!containerURL) {
		return 2;
	}

	NSUserDefaults *userDefaults = [[%c(NSUserDefaults) alloc] _initWithSuiteName:@"group.com.google.Gmail" container:containerURL];
	NSDictionary *accountIds = [userDefaults objectForKey:@"kGmailSharedStorageSignedInAccountIds"];

	if (!accountIds || accountIds.count == 0) {
		return 3;
	}

	// ***from gmailpushenabler by Leonard Hecker (https://gist.github.com/lhecker/00850043b35cf207cafc)
	NSMutableArray *accounts = [NSMutableArray arrayWithCapacity:accountIds.count];

	for (NSString *accountId in accountIds) {
		NSString *accountKey = [@"kGmailSharedStorageAddresses_" stringByAppendingString:accountId];
		NSArray *accountAddresses = [userDefaults objectForKey:accountKey];
		NSMutableSet *addressSet = [NSMutableSet setWithCapacity:accountAddresses.count];

		for (NSArray *addressInfo in accountAddresses) {
			if (addressInfo.count == 2) {
				[addressSet addObject:addressInfo[1]];
			}
		}

		[accounts addObject:addressSet];
	}

	sharedGmailAccounts = [accounts copy];
	// ***

	accounts = nil;
	accounts = [[NSMutableArray alloc] init];
	for (MailAccount *account in [%c(MailAccount) activeAccounts]) {
		NSString *address = [account firstEmailAddress] ?: nil;
		if (!address) continue;

		BOOL match = NO;
		for (NSSet *addressSet in sharedGmailAccounts) {
			if ([addressSet containsObject:address]) {
				match = YES;
				break;
			}
		}

		if (match) {
			 [accounts addObject:address];
		}
	}

	if (accounts.count == 0) {
		return 4;
	}

	iOSGmailAccounts = [accounts copy];

	TweakLog(@"loadGmailAccounts\n%@\n%@", iOSGmailAccounts, sharedGmailAccounts);

	return 0;
}

%group SpringBoardGroup
%hook SpringBoard
-(void)applicationDidFinishLaunching:(id)application
{
	%orig;

	dispatch_async(dispatch_get_main_queue(), ^{
		int result = loadGmailAccounts();

		NSMutableString *emailAddresses = [[NSMutableString alloc] init];
		if (result == 0) {
			for (NSSet *addressSet in sharedGmailAccounts) {
				BOOL match = NO;
				for (NSString *address in iOSGmailAccounts) {
					if ([addressSet containsObject:address]) {
						match = YES;
						break;
					}
				}

				if (!match) {
					if (emailAddresses.length) {
						[emailAddresses appendString:@"\n"];
					}
					[emailAddresses appendString:[addressSet anyObject]];
				}
			}

			if (emailAddresses.length) {
				result = 5;
			}
		}

		NSMutableDictionary *settings = [[NSMutableDictionary alloc] init];
		if (result != 0) {
			if (result == 1) {
				NSLog(@"[Gmailer] Error: Could not find Gmail application");
			} else if (result == 2) {
				NSLog(@"[Gmailer] Error: Could not find Gmail groupContainerURLs");
			} else if (result == 3) {
				NSLog(@"[Gmailer] Error: Could not find Gmail kGmailSharedStorageSignedInAccountIds");
			} else if (result == 4) {
				NSLog(@"[Gmailer] Error: Could not find iOS Gmail accounts");
			} else if (result == 5) {
				NSLog(@"[Gmailer] Warning: Some of your Gmail accounts do not have corresponding iOS accounts with the same email address");
				[settings setObject:emailAddresses forKey:@"message"];
			}

			[settings setObject:@(result) forKey:@"result"];
		}
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

%ctor
{
	@autoreleasepool {
		if (%c(SpringBoard)) {
			%init(SpringBoardGroup);
		} else {
			NSString *bundleIdentifier = [NSBundle mainBundle].bundleIdentifier;

			if ([bundleIdentifier isEqualToString:@"com.apple.mobilemail"]) {
				// %init(MailGroup);

				[[NSDistributedNotificationCenter defaultCenter] addObserverForName:@"net.tateu.gmailer/fetchAccount" object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *notification) {
					NSString *sender = notification.userInfo[@"sender"];
					AutoFetchController *autoFetchController = [objc_getClass("AutoFetchController") sharedController];

					if ([sender isEqualToString:@"Automatic"]) {
						NSMutableSet *accountsToFetch = [[NSMutableSet alloc] init];
						NSArray *emailAddresses = [notification.userInfo[@"emailAddresses"] componentsSeparatedByString:@","];

						if (emailAddresses && emailAddresses.count > 0) {
							for (NSString *emailAddress in emailAddresses) {
								MailAccount *account = [%c(MailAccount) accountContainingEmailAddress:emailAddress];

								if (account) {
									TweakLog(@"Fetch List %@", account);
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
