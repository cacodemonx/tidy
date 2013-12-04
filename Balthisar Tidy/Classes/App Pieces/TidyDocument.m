﻿/**************************************************************************************************

	TidyDocument.m

	part of Balthisar Tidy

	The main document controller. Here we'll control the following:

		o


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

/**************************************************************************************************
	NOTES ABOUT "DIRTY FILE" DETECTION
		We're doing a few convoluted things to allow undo in the
		|sourceView| while not messing up the document dirty flags.
		Essentially, whenever the |sourceView| <> |tidyView|, we're going
		to call it dirty. Whenever we write a file, it's obviously fit to be the source file,
		and we can then put it in the sourceView.
 **************************************************************************************************/

/**************************************************************************************************
	NOTES ABOUT TYPE/CREATOR CODES
		Mac OS X has killed type/creator codes. Oh well. But they're still supported
		and I continue to believe they're better than Windows-ish file extensions. We're going
		to try to make everybody happy by doing the following:
			o	For files that Tidy creates by the user typing into the sourceView, we'll save them
				with the Tidy type/creator codes. We'll use WWS2 for Balthisar Tidy creator, and
				TEXT for filetype. (I shouldn't use WWS2 'cos that's Balthisar Cascade type!!!).
			o	For *existing* files that Tidy modifies, we'll check to see if type/creator already
				exists, and if so, we'll re-write with the existing type/creator, otherwise we'll
				not use any type/creator and let the OS do its own thing in Finder.
 **************************************************************************************************/

#import "TidyDocument.h"
#import "PreferenceController.h"
#import "JSDTidyDocument.h"
#import "NSTextView+JSDExtensions.h"

#pragma mark - Non-Public iVars, Properties, and Method declarations

@interface TidyDocument ()
{
	JSDTidyDocument* tidyProcess;			// Our tidy wrapper/processor.
	NSInteger saveBehavior;					// The save behavior from the preferences.
	bool saveWarning;						// The warning behavior for when saveBehavior == 1;
	bool yesSavedAs;						// Disable warnings and protections once a save-as has been done.
	bool tidyOriginalFile;					// Flags whether the file was CREATED by Tidy, for writing type/creator codes.
}

@property (assign) IBOutlet NSSplitView *splitLeftRight;	// The left-right (main) split view in the Doc window.
@property (assign) IBOutlet NSSplitView *splitTopDown;		// Top top-to-bottom split view in the Doc window.

@end


#pragma mark - Implementation

@implementation TidyDocument


#pragma mark - File I/O Handling


/*———————————————————————————————————————————————————————————————————*
	readFromFile:
		Called as part of the responder chain. We already have a
		name and type as a result of
			(1) the file picker, or
			(2) opening a document from Finder. 
		Here, we'll merely load the file contents into an NSData,
		and process it when the nib awakes (since we're	likely to be
		called here before the nib and its controls exist).
 *———————————————————————————————————————————————————————————————————*/
- (BOOL)readFromFile:(NSString *)filename ofType:(NSString *)docType
{
	[tidyProcess setOriginalTextWithData:[NSData dataWithContentsOfFile:filename]]; // Give our tidyProcess the data.
	tidyOriginalFile = NO;															// The current file was OPENED, not a Tidy original.
	return YES;																		// Yes, it was loaded successfully.
}


/*———————————————————————————————————————————————————————————————————*
	dataOfType:error
		Called as a result of saving files. All we're going to do is
		pass back the NSData taken from the TidyDoc
 *———————————————————————————————————————————————————————————————————*/
- (NSData *)dataOfType:(NSString *)typeName error:(NSError **)outError
{
	return [tidyProcess tidyTextAsData];						// Return the raw data in user-encoding to be written.
}


/*———————————————————————————————————————————————————————————————————*
	writeToUrl:ofType:Error
		Called as a result of saving files, and does the actual
		writing. We're going to override it so that we can update
		the |sourceView| automatically any time the file is saved.
		The logic is once the file is saved the |sourceview| ought
		to reflect the actual file contents, which is the tidy'd
		view.
 *———————————————————————————————————————————————————————————————————*/
- (BOOL)writeToURL:(NSURL *)absoluteURL ofType:(NSString *)typeName error:(NSError **)outError
{
	//bool success = [super writeToFile:fileName ofType:type];	// Inherited method does the actual saving
	bool success = [super writeToURL:absoluteURL ofType:typeName error:outError];
	if (success)
	{
		[tidyProcess setOriginalText:[tidyProcess tidyText]];	// Make the |tidyText| the new |originalText|.
		[_sourceView setString:[tidyProcess workingText]];		// Update the |sourceView| with the newly-saved contents.
		yesSavedAs = YES;										// This flag disables the warnings, since they're meaningless now.
	}
	return success;
}


/*———————————————————————————————————————————————————————————————————*
	fileAttributesToWriteToURL:ofType:forSaveOperation:originalContentsURL:error:
		Called as a result of saving files. We're going to support the
		use of HFS+ type/creator codes, since Cocoa doesn't do this
		automatically. We only do this on files that haven't been
		opened by Tidy. That way, Tidy-created documents show the Tidy
		icons, and documents that were merely opened retain thier
		original file associations. We COULD make this a preference
		item such that Tidy will always add type/creator codes.
 *———————————————————————————————————————————————————————————————————*/

- (NSDictionary *)fileAttributesToWriteToURL:(NSURL *)absoluteURL
									  ofType:(NSString *)typeName
							forSaveOperation:(NSSaveOperationType)saveOperation
						 originalContentsURL:(NSURL *)absoluteOriginalContentsURL
									   error:(NSError **)outError
{

	// Get the inherited dictionary.
	NSMutableDictionary *myDict = (NSMutableDictionary *)[super fileAttributesToWriteToURL:absoluteURL
																					ofType:typeName
																		  forSaveOperation:saveOperation
																		originalContentsURL:absoluteOriginalContentsURL
																					 error:outError];
	
	// ONLY add type/creator if this is an original file -- NOT if we opened the file.
	if (tidyOriginalFile)
	{
		myDict[NSFileHFSCreatorCode] = @('WWS2');	// set creator code.
		myDict[NSFileHFSTypeCode] = @('TEXT');		// set file type.
	}
	else
	{
		// Use original type/creator codes, if any.
		OSType macType = [ [ [ NSFileManager defaultManager ] attributesOfItemAtPath:[absoluteURL path] error:nil ] fileHFSTypeCode];
		OSType macCreator = [ [ [ NSFileManager defaultManager ] attributesOfItemAtPath:[absoluteURL path] error:nil ] fileHFSCreatorCode];
		if ((macType != 0) && (macCreator != 0))
		{
			myDict[NSFileHFSCreatorCode] = @(macCreator);
			myDict[NSFileHFSTypeCode] = @(macType);
		}
	}
	return myDict;
}



/*———————————————————————————————————————————————————————————————————*
	revertToSavedFromFile:ofType
		Allow the default reversion to take place, and then put the
		correct value in the editor if it took place. The inherited
		method does |readFromFile|, so our |tidyProcess| will already
		have the reverted data.
 *———————————————————————————————————————————————————————————————————*/
- (BOOL)revertToSavedFromFile:(NSString *)fileName ofType:(NSString *)type
{
	bool didRevert = [super revertToSavedFromFile:fileName ofType:type];
	if (didRevert)
	{
		[_sourceView setString:[tidyProcess workingText]];	// Update the display, since the reversion already loaded the data.
		[self retidy];										// Re-tidy the document.
	}
	return didRevert;										// Flag whether we reverted or not.
}


/*———————————————————————————————————————————————————————————————————*
	saveDocument
		we're going to override the default save to make sure we can
		comply with the user's preferences. We're being over-protective
		because we want to not get blamed for screwing up the users'
		data if Tidy doesn't process something correctly.
 *———————————————————————————————————————————————————————————————————*/
- (IBAction)saveDocument:(id)sender
{
	// Normal save, but with a warning and chance to back out. Here's the logic for how this works:
	// (1) the user requested a warning before overwriting original files.
	// (2) the |sourceView| isn't empty.
	// (3) the file hasn't been saved already. This last is important, because if the file has
	//		already been edited and saved, there's no longer an "original" file to protect.

	// Warning will only apply if there's a current file and it's NOT been saved yet, and it's not new.
	if ( (saveBehavior == 1) && 				// Behavior is protective AND
		(saveWarning) &&						// We want to have a warning AND
		(yesSavedAs == NO) && 					// We've NOT yet done a save as... AND
		([[[self fileURL] path] length] != 0 ))	// The file name isn't zero length.
	{
		NSInteger i = NSRunAlertPanel(NSLocalizedString(@"WarnSaveOverwrite", nil), NSLocalizedString(@"WarnSaveOverwriteExplain", nil),
									  NSLocalizedString(@"continue save", nil),NSLocalizedString(@"do not save", nil) , nil);
		if (i == NSAlertAlternateReturn)
		{
			return; // Don't continue the save operation if user chose don't save.
		}
	}

	// Save is completely disabled -- tell user to Save As…
	if (saveBehavior == 2)
	{
		NSRunAlertPanel(NSLocalizedString(@"WarnSaveDisabled", nil), NSLocalizedString(@"WarnSaveDisabledExplain", nil),
						NSLocalizedString(@"cancel", nil), nil, nil);
		return; // Don't continue the save operation
	} // if

	return [super saveDocument:sender];
}


#pragma mark - Initialization, Destruction, and Setup


/*———————————————————————————————————————————————————————————————————*
	init
		Our creator -- create the |tidyProcess| and the |processString|.
		Also be registered to receive preference notifications for the
		file-saving preferences.
 *———————————————————————————————————————————————————————————————————*/
- (id)init
{
	self = [super init];
	if (self)
	{
		tidyOriginalFile = YES;							// If yes, we'll write file/creator codes.
		tidyProcess = [[JSDTidyDocument alloc] init];	// Use our own |tidyProcess|, NOT the controller's instance.
		// register for notification
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleSavePrefChange:) name:@"JSDSavePrefChange" object:nil];
	}
	
	return self;
}


/*———————————————————————————————————————————————————————————————————*
	dealloc
 *———————————————————————————————————————————————————————————————————*/
- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];	// remove ourselves from the notification center!
	[tidyProcess release];			// Release the tidyProcess.
	[_optionController release];	// Remove the optionController pane.
	[super dealloc];				// Do the inherited dealloc.
}


/*———————————————————————————————————————————————————————————————————*
	configureViewSettings
		given aView, make it non-wrapping. Also set fonts.
 *———————————————————————————————————————————————————————————————————*/
- (void)configureViewSettings:(NSTextView *)aView
{
	[aView setFont:[NSFont fontWithName:@"Courier" size:12]];	// Set the font for the views.
	[aView setRichText:NO];										// Don't allow rich text.
	[aView setUsesFontPanel:NO];								// Don't allow the font panel.
	[aView setContinuousSpellCheckingEnabled:NO];				// Turn off spell checking.
	[aView setSelectable:YES];									// Text can be selectable.
	[aView setEditable:NO];										// Text shouldn't be editable.
	[aView setImportsGraphics:NO];								// Don't let user import graphics.
	[aView setWordwrapsText:NO];								// Provided by category `NSTextView+JSDExtensions`
	[aView setShowsLineNumbers:YES];							// Provided by category `NSTextView+JSDExtensions`

}


/*———————————————————————————————————————————————————————————————————*
	awakeFromNib
		When we wake from the nib file, setup the option controller
		This will receive notifications when an option changes.
 *———————————————————————————————————————————————————————————————————*/
- (void) awakeFromNib
{
	// Create a OptionPaneController and put it in place of optionPane
	if (!_optionController)
	{
		_optionController = [[OptionPaneController alloc] init];
	}
	[_optionController putViewIntoView:_optionPane];
	[_optionController setTarget:self];
	[_optionController setAction:@selector(optionChanged:)];
}


/*———————————————————————————————————————————————————————————————————*
	windowControllerDidLoadNib:
		The nib is loaded. If there's a string in processString, it
		will appear in the |sourceView|.
 *———————————————————————————————————————————————————————————————————*/
- (void)windowControllerDidLoadNib:(NSWindowController *) aController
{
	[super windowControllerDidLoadNib:aController];								// Inherited method needs to be called.

	[self configureViewSettings:_sourceView];
	[self configureViewSettings:_tidyView];
	[_sourceView setEditable:YES];

	// Honor the defaults system defaults.
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];			// Get the default default system
	[[_optionController tidyDocument] takeOptionValuesFromDefaults:defaults];	// Make the optionController take the values

	// Saving behavior settings
	saveBehavior = [defaults integerForKey:JSDKeySavingPrefStyle];
	saveWarning = [defaults boolForKey:JSDKeyWarnBeforeOverwrite];
	yesSavedAs = NO;

	// Make the |sourceView| string the same as our loaded text.
	[_sourceView setString:[tidyProcess workingText]];

	// Force the processing to occur.
	[self optionChanged:self];
}


/*———————————————————————————————————————————————————————————————————*
	windowNibName
		Return the name of the Nib associated with this class.
 *———————————————————————————————————————————————————————————————————*/
- (NSString *)windowNibName
{
	return @"TidyDocument";
}


#pragma mark - Preferences, Tidy Options, and Tidy'ing


/*———————————————————————————————————————————————————————————————————*
	handleSavePrefChange
		This method receives "JSDSavePrefChange" notifications so
		we can keep abreast of the user's desired "Save" behaviours.
 *———————————————————————————————————————————————————————————————————*/
- (void)handleSavePrefChange:(NSNotification *)note
{
	saveBehavior = [[NSUserDefaults standardUserDefaults] integerForKey:JSDKeySavingPrefStyle];
	saveWarning = [[NSUserDefaults standardUserDefaults] boolForKey:JSDKeyWarnBeforeOverwrite];
}


/*———————————————————————————————————————————————————————————————————*
	retidy
		Perform the actual re-tidy'ing
 *———————————————————————————————————————————————————————————————————*/
- (void)retidy
{
	[tidyProcess setWorkingText:[_sourceView string]];		// Put the |sourceView| text into the |tidyProcess|.
	[_tidyView setString:[tidyProcess tidyText]];			// Put the tidy'd text into the |tidyView|.
	[_errorView reloadData];								// Reload the error data.
	[_errorView deselectAll:self];							// Deselect the selected row.

	// Handle document dirty detection -- we're NOT dirty if the source and tidy string are
	// the same, or there is no source view, of if the source is the same as the original.
	if ( ( [tidyProcess areEqualOriginalTidy]) ||			// The original text and tidy text are equal OR
		( [[tidyProcess originalText] length] == 0 ) ||		// The originalText was never there OR
		( [tidyProcess areEqualOriginalWorking ] ))			// The workingText is the same as the original.
	{
		[self updateChangeCount:NSChangeCleared];
	}
	else
	{
		[self updateChangeCount:NSChangeDone];
	}
}


#pragma mark - Event Handling


/*———————————————————————————————————————————————————————————————————*
	textDidChange:
		We arrived here by virtue of this document class being the
		delegate of |sourceView|. Whenever the text changes, let's
		reprocess all of the text. Hopefully the user won't be
		inclined to type everything, 'cos this is bound to be slow.
 *———————————————————————————————————————————————————————————————————*/
- (void)textDidChange:(NSNotification *)aNotification
{
	[self retidy];
}


/*———————————————————————————————————————————————————————————————————*
	optionChanged:
		One of the options changed! We're here by virtue of being the
		action of the optionController instance. Let's retidy here.
 *———————————————————————————————————————————————————————————————————*/
- (IBAction)optionChanged:(id)sender
{
	[tidyProcess optionCopyFromDocument:[_optionController tidyDocument]];
	[self retidy];
}


#pragma mark - Support for the Error Table


/*———————————————————————————————————————————————————————————————————*
	numberOfRowsInTableView
		We're here because we're the datasource of the table view.
		We need to specify how many items are in the table view.
 *———————————————————————————————————————————————————————————————————*/
- (NSUInteger)numberOfRowsInTableView:(NSTableView *)aTableView
{
	return [[tidyProcess errorArray] count];
}


/*———————————————————————————————————————————————————————————————————*
	tableView:objectValueForTableColumn:row
		We're here because we're the datasource of the table view.
		We need to specify what to show in the row/column.
 *———————————————————————————————————————————————————————————————————*/
- (id)tableView:(NSTableView *)aTableView objectValueForTableColumn:(NSTableColumn *)aTableColumn row:(int)rowIndex
{
	NSDictionary *error = [tidyProcess errorArray][rowIndex];	// Get the current error

	// List of error types -- no localized; users can localize based on this string.
	NSArray *errorTypes = @[@"Info:", @"Warning:", @"Config:", @"Access:", @"Error:", @"Document:", @"Panic:"];

	// Handle returning the severity of the error, localized.
	if ([[aTableColumn identifier] isEqualToString:@"severity"])
	{
		return NSLocalizedString(errorTypes[[error[@"level"] intValue]], nil);
	}

	// Handle the location, localized, or "N/A" if not applicable
	if ([[aTableColumn identifier] isEqualToString:@"where"])
	{
		if (([error[@"line"] intValue] == 0) || ([error[@"column"] intValue] == 0))
		{
			return NSLocalizedString(@"N/A", nil);
		}
		return [NSString stringWithFormat:@"%@ %@, %@ %@", NSLocalizedString(@"line", nil), error[@"line"], NSLocalizedString(@"column", nil), error[@"column"]];
	}

	if ([[aTableColumn identifier] isEqualToString:@"description"])
	{
		return error[@"message"];
	}
	
	return @"";
}


/*———————————————————————————————————————————————————————————————————*
	errorClicked:
		We arrived here by virtue of this controller class and this
		method being the action of the table. Whenever the selection
		changes we're going to highlight and show the related
		column/row in the sourceView.
 *———————————————————————————————————————————————————————————————————*/
- (IBAction)errorClicked:(id)sender
{
	NSInteger errorViewRow = [_errorView selectedRow];
	if (errorViewRow >= 0)
	{
		NSInteger row = [[tidyProcess errorArray][errorViewRow][@"line"] intValue];
		NSInteger col = [[tidyProcess errorArray][errorViewRow][@"column"] intValue];
		[_sourceView highlightLine:row Column:col];
	}
	else 
	{
		[_sourceView setShowsHighlight:NO];
	}
}


/*———————————————————————————————————————————————————————————————————*
	tableViewSelectionDidChange:
		We arrived here by virtue of this controller class being the
		delegate of the table. Whenever the selection changes
		we're going to highlight and show the related column/row
		in the |sourceView|.
 *———————————————————————————————————————————————————————————————————*/
- (void)tableViewSelectionDidChange:(NSNotification *)aNotification
{
	// Get the description of the selected row.
	if ([aNotification object] == _errorView)
	{
		[self errorClicked:self];
	}
}


#pragma mark - Split View Handling


/*–––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––*
	splitView:constrainMinCoordinate:ofSubviewAt:
		We're here because we're the delegate of the split views.
		This allows us to set the minimum constrain of the left/top
		item in a splitview. Must coordinate max to ensure others
		have space, too.
 *–––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––*/
- (CGFloat)splitView:(NSSplitView *)splitView constrainMinCoordinate:(CGFloat)proposedMinimumPosition ofSubviewAt:(NSInteger)dividerIndex
{
	// The main splitter
	if (splitView == _splitLeftRight)
	{
		return 250.0f;
	}
	
	// The text views' first splitter
	if (dividerIndex == 0)
	{
		return 68.0f;
	}
	
	// The text views' second splitter is first plus 68.0f;
    return [[[splitView subviews] objectAtIndex:0] frame].size.height + 68.0f;
}

/*–––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––*
	splitView:constrainMaxCoordinate:ofSubviewAt:
		We're here because we're the delegate of the split views.
 *–––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––*/
- (CGFloat)splitView:(NSSplitView *)splitView constrainMaxCoordinate:(CGFloat)proposedMinimumPosition ofSubviewAt:(NSInteger)dividerIndex
{
	// The main splitter
	if (splitView == _splitLeftRight)
	{
		return [splitView frame].size.width - 150.0f;
	}
	
	// The text views' first splitter
	if (dividerIndex == 0)
	{
		return [[[splitView subviews] objectAtIndex:0] frame].size.height +
				[[[splitView subviews] objectAtIndex:1] frame].size.height - 68.0f;
	}
	
	
	// The text views' second splitter
	return [splitView frame].size.height - 68.0f;	
}

/*–––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––*
	splitView:shouldAdjustSizeOfSubview:
		We're here because we're the delegate of the split views.
		Prevent the left pane from resizing during window resize.
 *–––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––*/
- (BOOL)splitView:(NSSplitView *)splitView shouldAdjustSizeOfSubview:(NSView *)subview
{
	if (splitView == _splitLeftRight)
	{
		if (subview == [[_splitLeftRight subviews] objectAtIndex:0])
		{
			return NO;
		}
	}
	return YES;
}


@end
