#import <Foundation/NSDistributedNotificationCenter.h>
#import <Preferences/Preferences.h>
#import "../headers.h"

// #define DEBUG
#ifdef DEBUG
#define TweakLog(fmt, ...) NSLog((@"[GmailerSettings] [Line %d]: "  fmt), __LINE__, ##__VA_ARGS__)
#else
#define TweakLog(fmt, ...)
#define NSLog(fmt, ...)
#endif

#define plistfile @"/var/mobile/Library/Preferences/net.tateu.gmailer.plist"
static NSMutableDictionary *settings;

@interface GmailerListController: PSListController {
	NSMutableArray *activeAccounts;
}
- (void)fetchForAccount:(id)sender;
- (void)showResultMessage:(id)sender;
- (void)relinkEmailAccounts;
@end

@implementation GmailerListController
- (void)relinkEmailAccounts
{
	[[NSDistributedNotificationCenter defaultCenter] postNotificationName:@"net.tateu.gmailer/relinkEmailAccounts" object:nil userInfo:nil];
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (5) * NSEC_PER_SEC), dispatch_get_main_queue(), ^(void) {
		settings = [NSMutableDictionary dictionaryWithContentsOfFile:plistfile] ?: [NSMutableDictionary dictionary];
		[self reloadSpecifiers];
		[self reload];
	});
}

- (void)fetchForAccount:(PSSpecifier *)specifier
{
	int index = [specifier propertyForKey:@"index"] ? [[specifier propertyForKey:@"index"] intValue] : -1;
	if (index >= 0 && index < [activeAccounts count]) {
		MailAccount *account = [activeAccounts objectAtIndex:index];
		TweakLog(@"fetchForAccount %d\n%@\n%@\n%@\n%@", index, specifier, account, [account uniqueIdForPersistentConnection], [account primaryMailboxUid]);
		[[NSDistributedNotificationCenter defaultCenter] postNotificationName:@"net.tateu.gmailer/fetchAccount" object:nil userInfo:@{@"sender" : [account uniqueIdForPersistentConnection]}];
	}
}

- (void)showResultMessage:(PSSpecifier *)specifier
{
	NSString *message;
	int index = [specifier propertyForKey:@"index"] ? [[specifier propertyForKey:@"index"] intValue] : -1;
	if (index == 0) {
		message = [specifier propertyForKey:@"label"];
	} else if (index == 1) {
		message = @"Please make sure that the Gmail app is installed, your accounts are configured and make sure you open the app atleast once after installing Gmailer.\n\nIf you've recently made changes to any of your iOS Gmail related accounts in Settings -> Mail, Contacts, Calendars, please respring your device.\n\nThis is a fatal error.";
	} else if (index == 4) {
		message = @"It appears that you do not have any iOS mail accounts configured and enabled that match what is set up in the Gmail app.\nYou should go to 'Settings -> Mail, Contacts, Calendars', add and configure your accounts, then respring.\n\nThis is a fatal error.";
	} else if (index == 5) {
		message = [NSString stringWithFormat:@"It appears that you have some accounts configured in the Gmail app that are not configured in iOS.\nSome of your accounts will not work.\n\n%@\n\nIf you've recently made changes to any of your iOS Gmail related accounts in Settings -> Mail, Contacts, Calendars, please respring your device.", [specifier propertyForKey:@"label"]];
	} else {
		message = @"Unkown error";
	}

	UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:@"Gmailer" message:message delegate:self cancelButtonTitle:@"Ok" otherButtonTitles:nil];
	[alertView show];
}

- (id)specifiers
{
	if(_specifiers == nil) {
		_specifiers = [self loadSpecifiersFromPlistName:@"Gmailer" target:self];
		PSSpecifier *specifier = nil;

		// if (settings[@"result"]) {
			int result = settings[@"result"] ? [settings[@"result"] intValue] : 1;
			if (result > 0) {
				NSString *title = @"Errors";

				if (result == 5) {
					title = @"Warnings";
				}

				specifier = [PSSpecifier preferenceSpecifierNamed:title
															target:self
															   set:nil
															   get:nil
															detail:nil
															  cell:PSGroupCell
															  edit:nil];

				[(NSMutableArray *)_specifiers insertObject:specifier atIndex:0];

				if (result == 1) {
					title = @"Gmail App not configured";
				} else if (result == 2) {
					title = @"Gmail App not installed correctly";
				} else if (result == 3) {
					title = @"No accounts enabled in Gmail App";
				} else if (result == 4) {
					title = @"No iOS Gmail accounts are enabled";
				} else if (result == 5) {
					title = [NSString stringWithFormat:@"Some Gmail accounts do not match iOS accounts"];
				}

				specifier = [PSSpecifier preferenceSpecifierNamed:title
															target:self
															   set:nil
															   get:nil
															detail:nil
															  cell:PSButtonCell
															  edit:nil];

				specifier->action = @selector(showResultMessage:);
				[specifier setProperty:title forKey:@"title"];
				if (result == 5) [specifier setProperty:settings[@"message"] forKey:@"label"];
				[specifier setProperty:@(result) forKey:@"index"];

				[(NSMutableArray *)_specifiers insertObject:specifier atIndex:1];
			}
		// }

		if (settings[@"trackedAccounts"]) {
			specifier = [PSSpecifier preferenceSpecifierNamed:@"Tracked Accounts"
														target:self
														   set:nil
														   get:nil
														detail:nil
														  cell:PSGroupCell
														  edit:nil];

			[(NSMutableArray *)_specifiers addObject:specifier];

			for (NSString *trackedAccount in settings[@"trackedAccounts"]) {

  				specifier = [PSSpecifier preferenceSpecifierNamed:trackedAccount
  															target:self
  															   set:nil
  															   get:nil
  															detail:nil
  															  cell:PSButtonCell
  															  edit:nil];

				specifier->action = @selector(showResultMessage:);
				[specifier setProperty:trackedAccount forKey:@"title"];
				[specifier setProperty:trackedAccount forKey:@"label"];
				[specifier setProperty:@(0) forKey:@"index"];

				[(NSMutableArray *)_specifiers addObject:specifier];
			}
		}

		specifier = [PSSpecifier preferenceSpecifierNamed:@"Fetch Now"
													target:self
													   set:nil
													   get:nil
													detail:nil
													  cell:PSGroupCell
													  edit:nil];
		// [specifier setProperty:@"***This setting causes Gmailer to fetch all tracked accounts upon receiving any push notification for the Gmail app. This may help you if Gmailer is not properly associating notifications with your accounts or if Gmail itself is having technical issues.\n\n***This is off by default because it may unnecessarily increase network activity, somewhat increasing battery usage." forKey:@"footerText"];

		[(NSMutableArray *)_specifiers addObject:specifier];

		activeAccounts = [[NSMutableArray alloc] init];
		int i = 0;

		for (MailAccount *account in [%c(MailAccount) activeAccounts]) {
			if (![account isKindOfClass:%c(LocalAccount)]) {
				NSString *displayName = [account displayName];
				[activeAccounts addObject:account];

				PSSpecifier *specifier = [PSSpecifier preferenceSpecifierNamed:displayName
																		target:self
																		   set:nil
																		   get:nil
																		detail:nil
																		  cell:PSButtonCell
																		  edit:nil];

				specifier->action = @selector(fetchForAccount:);
				[specifier setProperty:displayName forKey:@"title"];
				[specifier setProperty:displayName forKey:@"label"];
				[specifier setProperty:[NSNumber numberWithInt:i++] forKey:@"index"];

				[(NSMutableArray *)_specifiers addObject:specifier];
			}
		}
	}
	return _specifiers;
}

- (id)initForContentSize:(CGSize)size
{
	if ((self = [super initForContentSize:size]) != nil) {
		settings = [NSMutableDictionary dictionaryWithContentsOfFile:plistfile] ?: [NSMutableDictionary dictionary];
	}

	return self;
}

-(void)viewWillAppear:(BOOL)animated
{
	settings = ([NSMutableDictionary dictionaryWithContentsOfFile:plistfile] ?: [NSMutableDictionary dictionary]);
	[super viewWillAppear:animated];
	[self reload];
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier
{
	[settings setObject:value forKey:specifier.properties[@"key"]];
	[settings writeToFile:plistfile atomically:YES];

	NSString *post = specifier.properties[@"PostNotification"];
	if (post) {
		CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),  (__bridge CFStringRef)post, NULL, NULL, TRUE);
	}
}

- (id)readPreferenceValue:(PSSpecifier *)specifier
{
	NSString *key = [specifier propertyForKey:@"key"];
	id defaultValue = [specifier propertyForKey:@"default"];
	id plistValue = [settings objectForKey:key];
	if (!plistValue) plistValue = defaultValue;

	return plistValue;
}

- (id)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
	PSControlTableCell *cell = [super tableView:tableView cellForRowAtIndexPath:indexPath];
	if ([cell isKindOfClass:%c(PSSwitchTableCell)]) {
		if (indexPath.section == 1 && indexPath.row == 0) {
			int result = settings[@"result"] ? [settings[@"result"] intValue] : 1;
			UISwitch *contactSwitch = (UISwitch *)cell.control;
			if (result == 5) {
				contactSwitch.onTintColor = [UIColor orangeColor];
			} else {
				contactSwitch.onTintColor = [UIColor redColor];
			}
		} else if (/*indexPath.section == 0 &&*/ indexPath.row == 1 || indexPath.row == 2) {
			UISwitch *contactSwitch = (UISwitch *)cell.control;
			contactSwitch.onTintColor = [UIColor blackColor];
		}
	}

	return cell;
}
@end
