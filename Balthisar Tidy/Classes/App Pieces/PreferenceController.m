/**************************************************************************************************

	PreferenceController.m

	part of Balthisar Tidy

	The main preference controller. Here we'll control the following:

		o Handles the application preferences.
		o Implements class methods to be used before instantiation.


	The MIT License (MIT)

	Copyright (c) 2001 to 2013 James S. Derry <http://www.balthisar.com>

	Permission is hereby granted, free of charge, to any person obtaining a copy of this software
	and associated documentation files (the "Software"), to deal in the Software without
	restriction, including without limitation the rights to use, copy, modify, merge, publish,
	distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the
	Software is furnished to do so, subject to the following conditions:

	The above copyright notice and this permission notice shall be included in
	all copies or substantial portions of the Software.

	THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING
	BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
	NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM,
	DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
	OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

 **************************************************************************************************/

#import <Cocoa/Cocoa.h>
#import "PreferenceController.h"
#import "JSDTidyDocument.h"


@implementation PreferenceController


#pragma mark - CLASS METHODS


/*–––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––*
	registerUserDefaults
		Register all of the user defaults. Implemented as a CLASS
		method in order to keep this with the preferences controller.
 *–––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––*/
+ (void)registerUserDefaults
{
	NSMutableDictionary *defaultValues = [NSMutableDictionary dictionary];
	
	// Put all of the defaults in the dictionary
	defaultValues[JSDKeySavingPrefStyle] = @(kJSDSaveAsOnly);
	defaultValues[JSDKeyWarnBeforeOverwrite] = @NO;
	
	// Get the defaults from the linked-in TidyLib
	[JSDTidyDocument addDefaultsToDictionary:defaultValues];
	
	// Register the defaults with the defaults system
	[[NSUserDefaults standardUserDefaults] registerDefaults: defaultValues];
}


#pragma mark - INITIALIZATION and DESTRUCTION and SETUP


/*–––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––*
	init
 *–––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––*/
- (id)init
{
	if (self = [super initWithWindowNibName:@"Preferences"])
	{
		[self setWindowFrameAutosaveName:@"PrefWindow"];
	}
	return self;
}


/*–––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––*
	dealloc
 *–––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––*/
- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self
													name:tidyNotifyOptionChanged
												  object:nil];
	_tidyProcess = nil;
}


/*–––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––*
	awakeFromNib
		Create an |OptionPaneController| and put it
		in place of the empty optionPane in the xib.
 *–––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––*/
- (void) awakeFromNib
{
	if (![self optionController])
	{
		self.optionController = [[OptionPaneController alloc] init];
	}
	
	[[self optionController] putViewIntoView:[self optionPane]];
	
	self.tidyProcess = [[self optionController] tidyDocument];
}


/*–––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––*
	windowDidLoad
		Use the defaults to setup the correct preferences settings.
 *–––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––*/
- (void)windowDidLoad
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	
	[[self saving1] setState:([defaults integerForKey: JSDKeySavingPrefStyle] == kJSDSaveButWarn)];
	[[self saving2] setState:([defaults integerForKey: JSDKeySavingPrefStyle] == kJSDSaveAsOnly)];
	[[self savingWarn] setState:[defaults boolForKey: JSDKeyWarnBeforeOverwrite]];
	[[self savingWarn] setEnabled:[[self saving1] state]];

	
	// Put the Tidy defaults into the |tidyProcess|.
	[[self tidyProcess] takeOptionValuesFromDefaults:defaults];
	
	
	// NSNotifications from |optionController| indicate that one or more Tidy options changed.
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(handleTidyOptionChange:)
												 name:tidyNotifyOptionChanged
											   object:[[self optionController] tidyDocument]];
}


#pragma mark - Events


/*–––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––*
	radioSavingChanged
		One of the radio buttons for saving options has changed.
		Handle this apart, since we're not using a matrix.
 *–––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––*/
- (IBAction)radioSavingChanged:(id)sender
{
	[[self saving1] setState:NO];
	[[self saving2] setState:NO];
	[sender setState:YES];
	[[self savingWarn] setEnabled:[[self saving1] state]];
	[self preferenceChanged:nil];
}


/*–––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––*
	preferenceChanged
		One of the saving prefs changed. Log and notify.
 *–––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––*/
- (IBAction)preferenceChanged:(id)sender
{
	[[NSUserDefaults standardUserDefaults] setInteger:kJSDSaveNoProtection forKey:JSDKeySavingPrefStyle];
	
	if ([[self saving1] state])
	{
		[[NSUserDefaults standardUserDefaults] setInteger:kJSDSaveButWarn forKey:JSDKeySavingPrefStyle];
	}
	
	if ([[self saving2] state])
	{
		[[NSUserDefaults standardUserDefaults] setInteger:kJSDSaveAsOnly forKey:JSDKeySavingPrefStyle];
	}
	
	[[NSUserDefaults standardUserDefaults] setBool:[[self savingWarn] state] forKey:JSDKeyWarnBeforeOverwrite];
	
	[[NSNotificationCenter defaultCenter] postNotificationName:JSDSavePrefChange object:nil];
}


/*–––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––*
	handleTidyOptionChange
		We're here because we registered for NSNotification.
		One of the preferences changed in the table view.
		We're going to record the preference,
		but we're not going to post a notification, 'cos new
		documents will read the preferences themselves.
 *–––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––*/
- (void)handleTidyOptionChange:(NSNotification *)note
{
	[[self tidyProcess] writeOptionValuesWithDefaults:[NSUserDefaults standardUserDefaults]];
}

@end
