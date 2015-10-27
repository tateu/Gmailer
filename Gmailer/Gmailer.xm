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
// - (void)showResultMessage:(id)sender;
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

// - (void)showResultMessage:(PSSpecifier *)specifier
// {
// 	UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:title message:[NSString stringWithFormat:@"message] delegate:self cancelButtonTitle:@"Ok" otherButtonTitles:nil];
// }

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
				title = [NSString stringWithFormat:@"Some Gmail accounts do not match iOS accounts (%@)", settings[@"message"]];
			}

			specifier = [PSSpecifier preferenceSpecifierNamed:title
														target:self
														   set:nil
														   get:nil
														detail:nil
														  cell:PSStaticTextCell //PSButtonCell
														  edit:nil];

			// specifier->action = @selector(showResultMessage:);
			[specifier setProperty:title forKey:@"title"];
			[specifier setProperty:title forKey:@"label"];
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
