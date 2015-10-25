#import <Foundation/NSDistributedNotificationCenter.h>
#import "headers.h"

// #define DEBUG
#ifdef DEBUG
#define TweakLog(fmt, ...) NSLog((@"[Gmailer] [Line %d]: "  fmt), __LINE__, ##__VA_ARGS__)
#else
#define TweakLog(fmt, ...)
#define NSLog(fmt, ...)
#endif

static NSArray *accounts = nil;
static PCSimpleTimer *updateTimer = nil;

%group SpringBoardGroup
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

	if (info[@"APSMessageTopic"] && [info[@"APSMessageTopic"] isEqualToString:@"com.google.Gmail"]) {
		NSMutableSet *emailAddresses;
		NSString *emailAddress = nil;
		NSDictionary *APSMessageUserInfo = info[@"APSMessageUserInfo"];
		if (APSMessageUserInfo[@"a"]) {
			NSInteger index = [APSMessageUserInfo[@"a"] intValue] - 1;
			if (accounts && index < [accounts count]) {
				emailAddress = [accounts objectAtIndex:index];
			}
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

static void loadGmailAccounts()
{
	NSMutableArray *preSort = [[NSMutableArray alloc] init];
	for (MailAccount *account in [%c(MailAccount) activeAccounts]) {
		if ([account isKindOfClass:%c(GmailAccount)]) {
			[preSort addObject:[account firstEmailAddress]];
		}
	}

	accounts = [[preSort sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)] copy];
	TweakLog(@"loadGmailAccounts\n%@\n%@", preSort, accounts);
}

%ctor
{
	@autoreleasepool {
		if (%c(SpringBoard)) {
			loadGmailAccounts();
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
						// NSArray *emailAddresses = [notification.userInfo[@"emailAddresses"] componentsSeparatedByString:@","];
						//
						// if (emailAddresses && [emailAddresses count] > 0) {
						// 	for (NSString *emailAddress in emailAddresses) {
						// 		MailAccount *account = [%c(MailAccount) accountContainingEmailAddress:emailAddress];
						//
						// 		if (account) {
						// 			TweakLog(@"Fetch List %@", account);
						// 			[accountsToFetch addObject:[[%c(MailboxSource) alloc] initWithMailbox:[account primaryMailboxUid]]];
						// 		}
						// 	}
						// } else {
							for (MailAccount *account in [%c(MailAccount) activeAccounts]) {
								if ([account isKindOfClass:%c(GmailAccount)]) {
									TweakLog(@"Fetch All %@", account);
									[accountsToFetch addObject:[[%c(MailboxSource) alloc] initWithMailbox:[account primaryMailboxUid]]];
								}
							}
						// }

						if ([accountsToFetch count] > 0) {
							[autoFetchController fetchNow:0 withSources:accountsToFetch];
						}
						accountsToFetch = nil;
					} else {
						MailAccount *account = [%c(MailAccount) accountWithUniqueId:sender];
						TweakLog(@"Fetch Preferences %@", account);
						MailboxSource *source = [[%c(MailboxSource) alloc] initWithMailbox:[account primaryMailboxUid]];
						[autoFetchController fetchNow:0 withSources:@[source]];
					}
				}];
			}
		}
	}
}
