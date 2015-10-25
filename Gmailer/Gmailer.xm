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

#define _plistfile @"/var/mobile/Library/Preferences/net.tateu.gmailer.plist"
static NSMutableDictionary *_settings;

@interface GmailerListController: PSListController {
	NSMutableArray *activeAccounts;
}
- (void)fetchForAccount:(id)sender;
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

- (id)specifiers
{
	if(_specifiers == nil) {
		_specifiers = [self loadSpecifiersFromPlistName:@"Gmailer" target:self];

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
		_settings = [NSMutableDictionary dictionaryWithContentsOfFile:_plistfile] ?: [NSMutableDictionary dictionary];
	}

	return self;
}

-(void)viewWillAppear:(BOOL)animated
{
	_settings = ([NSMutableDictionary dictionaryWithContentsOfFile:_plistfile] ?: [NSMutableDictionary dictionary]);
	[super viewWillAppear:animated];
	[self reload];
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier
{
	_settings = ([NSMutableDictionary dictionaryWithContentsOfFile:_plistfile] ?: [NSMutableDictionary dictionary]);
	[_settings setObject:value forKey:specifier.properties[@"key"]];
	[_settings writeToFile:_plistfile atomically:YES];

	NSString *post = specifier.properties[@"PostNotification"];
	if (post) {
		CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),  (__bridge CFStringRef)post, NULL, NULL, TRUE);
	}
}

- (id)readPreferenceValue:(PSSpecifier *)specifier
{
	NSString *key = [specifier propertyForKey:@"key"];
	id defaultValue = [specifier propertyForKey:@"default"];
	id plistValue = [_settings objectForKey:key];
	if (!plistValue) plistValue = defaultValue;

	return plistValue;
}
@end
