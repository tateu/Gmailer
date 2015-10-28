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
@end

@implementation GmailerListController
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
	if (index == 1) {
		message = @"It appears that the Gmail app is not installed on your device.\n\nYou should install it, open it, then configure and log into your accounts, then respring.\n\nThis is a fatal error.";
	} else if (index == 2) {
		message = @"It appears that the Gmail app is not setup correctly (groupContainerURLs not found).\n\nYou should open it, then configure and log into your accounts, then respring.\n\nThis is a fatal error.";
	} else if (index == 3) {
		message = @"It appears that you have not configured and enabled any accounts in the Gmail app.\n\nYou should open it, then configure and log into your accounts, then respring.\n\nThis is a fatal error.";
	} else if (index == 4) {
		message = @"It appears that you do not have any iOS mail accounts configured and enabled that match what is set up in the Gmail app.\nYou should go to 'Settings -> Mail, Contacts, Calendars', add and configure your accounts, then respring.\n\nThis is a fatal error.";
	} else if (index == 5) {
		message = [NSString stringWithFormat:@"It appears that you have some accounts configured in the Gmail app that are not also configured in iOS.\nSome of your accounts will not work.\n\n%@", [specifier propertyForKey:@"label"]];
	}
	UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:@"Gmailer" message:message delegate:self cancelButtonTitle:@"Ok" otherButtonTitles:nil];
	[alertView show];
}

- (id)specifiers
{
	if(_specifiers == nil) {
		_specifiers = [self loadSpecifiersFromPlistName:@"Gmailer" target:self];
		PSSpecifier *specifier = nil;

		if (settings[@"result"]) {
			int result = [settings[@"result"] intValue];
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

			[(NSMutableArray *)_specifiers addObject:specifier];

			if (result == 1) {
				title = @"Gmail App not installed";
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
														  cell:PSButtonCell //PSStaticTextCell PSButtonCell
														  edit:nil];

			specifier->action = @selector(showResultMessage:);
			[specifier setProperty:title forKey:@"title"];
			if (result == 5) [specifier setProperty:settings[@"message"] forKey:@"label"];
			[specifier setProperty:@(result) forKey:@"index"];

			[(NSMutableArray *)_specifiers addObject:specifier];
		}

		specifier = [PSSpecifier preferenceSpecifierNamed:@"Fetch Now"
													target:self
													   set:nil
													   get:nil
													detail:nil
													  cell:PSGroupCell
													  edit:nil];

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
@end
