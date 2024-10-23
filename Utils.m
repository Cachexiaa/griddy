#import "Utils.h"
BOOL needsRefresh;

NSUInteger findFirstOpenIndexInListStartingAt(NSArray *list, SBHIconGridSize gridSize, int start) {
    int size = gridSize.columns * gridSize.rows;
    //create an array that will store icon indexes
    BOOL helperBoolArray[size];
    
    for (int i = 0; i < size; i++) {
        helperBoolArray[i] = NO;
    }

    //loop through the array, and place all existing icons at their preferred(custom) indexes
    for (int i = 0; i < [list count]; i++) {
        SBIcon *icon = list[i];

        if ([icon isKindOfClass:NSClassFromString(@"SBPlaceholderIcon")]) continue;

        GriddyIconLocationPreferences *prefs = locationPrefs[icon.uniqueIdentifier];

        //check if the icon fits there
        //note: anything already drawn in up to that point will have higher priority
        NSUInteger idx = prefs.index;
        for (int k = 0; k < prefs.gridSize.rows; k++) {
            for (int j = 0; j < prefs.gridSize.columns; j++) {
                int tempIdx = (idx + j) + (k * gridSize.columns);
                helperBoolArray[tempIdx] = YES;
            }
        }

    }

    //find the first open index from start
    for (int i = start; i < size; i++) {
        if (!helperBoolArray[i]) {
            return i;
        }
    }

    return 0;
}
//checks if a give grid cell index is valid for an icon
BOOL checkValidIndexForIconSize(SBIconListGridCellInfo *info, SBHIconGridSize writeSize, long long writeIndex) {
    int cols = info.gridSize.columns;
    int rows = info.gridSize.rows;
    int totalLength = cols * rows;

    //outside of bounds
    if (writeIndex >= totalLength) return NO;
    //already has an icon in that spot
    if ([info iconIndexForGridCellIndex:writeIndex] < totalLength) return NO;
    //doesnt fit horizontally(example: a 2x2 widget placed with top left corner in the far right)
    if (!(((writeIndex % cols) + writeSize.columns) <= cols)) return NO;
    ////doestn fit vertically(example: a 2x2 widget placed with top left corner in the bottom row)
    if (!(((NSUInteger)(writeIndex / cols) + writeSize.rows) <= (rows))) return NO;
    
    //check every spot on the widget and see if theres already an icon there
    SBIconCoordinate coord = [info coordinateForGridCellIndex:writeIndex];
    for (int k = 0; k < writeSize.rows ; k++) {
        for (int j = 0; j < writeSize.columns; j++) {
            SBIconCoordinate tempCoord;
            tempCoord.column = coord.column + j;
            tempCoord.row = coord.row + k;
            if ([info iconIndexForGridCellIndex:[info gridCellIndexForCoordinate:tempCoord]] < totalLength) return NO;
        }
    }

    return YES;
}

//creates a new entry for a given icon
void createNewLocationPrefs(SBIconListModel *model, SBIcon *icon, long long idx) {
    GriddyIconLocationPreferences *prefs = [[GriddyIconLocationPreferences alloc] init];
    prefs.index = idx;
    prefs.ogIndex = prefs.index;
    
    prefs.gridSize = [model gridSizeForGridSizeClass:icon.gridSizeClass];
    //place icon at the end of priority for its given class
    prefs.priority = [icon isKindOfClass:NSClassFromString(@"SBWidgetIcon")] ? 99 : 999;


    locationPrefs[icon.uniqueIdentifier] = prefs;
}

NSArray *reorderIconListBasedOnCustomIndex(NSArray *iconList, int size) {
    //create a temporary array that will hold icon entries
    int tempArr[size];
    for (int i = 0; i < size; i++) {
        tempArr[i] = -1;
    }
    //for each icon, take its preferred(custom) index and put it at that spot
    for (int i = 0; i < [iconList count]; i++) {
        SBIcon *icon = iconList[i];
        GriddyIconLocationPreferences *prefs = locationPrefs[icon.uniqueIdentifier];
        tempArr[prefs.index] = i;
    }
    //go through the temporary array, and take any icons you find along the way, puttung them in a new array
    NSMutableArray *newList = [[NSMutableArray alloc] init];
    for (int i = 0; i < size; i++) {
        if (tempArr[i] != -1) {
            SBIcon *icon = iconList[tempArr[i]];
            [newList addObject:icon];
        }
    }
    //assign priorities to icons, in order of them showing up as well as based on their class
    int widgetCount = 0;
    for(int i = 0; i < [newList count]; i++) {
        SBIcon *icon = newList[i];
        GriddyIconLocationPreferences *prefs = locationPrefs[icon.uniqueIdentifier];
        //widgets get 0-99
        if ([icon isKindOfClass:NSClassFromString(@"SBWidgetIcon")]) {
            prefs.priority = widgetCount;
            widgetCount++;
        }
        //normal icons get 200+
        else {
            prefs.priority = 200+(i-widgetCount);
        }
    }

    //save to nsuserdefaults
    NSMutableDictionary *tempDict = [[NSMutableDictionary alloc] init];
    for (NSString *key in locationPrefs) {
        tempDict[key] = [NSNumber numberWithUnsignedLongLong:((GriddyIconLocationPreferences *)locationPrefs[key]).index];
    }

    [[NSUserDefaults standardUserDefaults] setObject:tempDict forKey:((screenOrientation == 0 ? @"GriddyPortraitSave" : @"GriddyLandscapeSave"))];

    return newList;
}

NSArray *patchGridCellInfoForIconList(NSArray *staticIconList, SBIconListGridCellInfo *info, SBIconListModel *model) {
    NSMutableArray *iconList = [staticIconList mutableCopy];
    if (info.gridSize.columns > 100 || info.gridSize.rows > 100) return staticIconList;
    [info clearAllIconAndGridCellIndexes];

    BOOL shouldPushDraggedIcons = YES;
    if ([draggedIcons count] > 0 && !creatingNewIcon) {
        for (int i = 0; i < [draggedIcons count]; i++) {
            if (![draggedIcons[i] isKindOfClass:NSClassFromString(@"SBPlaceholderIcon")] && ![staticIconList containsObject:draggedIcons[i]]) {
                shouldPushDraggedIcons = NO;
                break;
            }
        }
    } else {
        shouldPushDraggedIcons = NO;
    }

    //moved dragged icons up in priority to be rendered first
    if (shouldGivePriority && shouldPushDraggedIcons) {
        needsRefresh = YES;
        SBIcon *tempIcon;
        for (int i = 0; i < [draggedIcons count]; i++) {
            tempIcon = draggedIcons[i];
            if (![iconList containsObject:tempIcon]) continue;

            GriddyIconLocationPreferences *prefs = locationPrefs[tempIcon.uniqueIdentifier];
            prefs.priority = 100+i;

            //if the last existing icon in dragged is a placeholder, this means that the "real" icons have been placed already
            if ([tempIcon isKindOfClass:NSClassFromString(@"SBPlaceholderIcon")]) {
                if ([draggedIcons count] == 1) [draggedIcons removeAllObjects];
            } else {
                [draggedIcons removeObject:tempIcon];
                i--;
            }
            if ([draggedIcons count] == 0) shouldRedrawList = YES;
        }
        if ([draggedIcons count] == 1 && [draggedIcons[0] isKindOfClass:NSClassFromString(@"SBPlaceholderIcon")]) [draggedIcons removeAllObjects];
    } else if ([draggedIcons count] > 0) {
        //"real" icons havent been placed yet, so we need to bump the placeholder in priority
        needsRefresh = YES;
        SBIcon *tempIcon;
        for (int i = 0; i < [draggedIcons count]; i++) {
            tempIcon = draggedIcons[i];
            if ([iconList containsObject:tempIcon] && [tempIcon isKindOfClass:NSClassFromString(@"SBPlaceholderIcon")]) {
                GriddyIconLocationPreferences *prefs = locationPrefs[tempIcon.uniqueIdentifier];
                prefs.priority = 100+i;
            }
        }
    }

    //reorder the icon list based on priority, not an efficient sort but it works
    if (needsRefresh) {
        needsRefresh = NO;
        int size = [iconList count];
        BOOL swapFlag = NO;
        for (int i = 0; i < size; i++) {
            swapFlag = NO;
            for (int j = 0; j < size - i - 1; j++) {
                GriddyIconLocationPreferences *pref1 = locationPrefs[((SBIcon *)iconList[j]).uniqueIdentifier];
                if (pref1 == nil) break;
                GriddyIconLocationPreferences *pref2 = locationPrefs[((SBIcon *)iconList[j+1]).uniqueIdentifier];
                if (pref2 == nil) break;
                if (pref1.priority > pref2.priority) {
                    SBIcon *temp = iconList[j];
                    iconList[j] = iconList[j+1];
                    iconList[j+1] = temp;
                    swapFlag = true;
                }
            }
            if (!swapFlag) break;
        }
    }

    //this for loop is responsible for actually laying out the icons
    for (int i = 0; i < [iconList count]; i++) {
        SBIcon *icon = iconList[i];

        //mark folders to also support custom layouts
        if ([icon isKindOfClass:NSClassFromString(@"SBFolderIcon")]) {
            SBFolder *folder = ((SBFolderIcon *)icon).folder;
            for (int i = 0; i < [folder.lists count]; i++) {
                SBIconListModel *model = folder.lists[i];
                model.griddyShouldPatch = YES;
            }
        }

        //if, for some reason, we dont have an entry for an icon, we create a new one
        GriddyIconLocationPreferences *prefs = locationPrefs[icon.uniqueIdentifier];
        if (!prefs)  {
            createNewLocationPrefs(model, icon, (proposedIndex == -1) ? findFirstOpenIndexInListStartingAt(iconList, info.gridSize, 0) : proposedIndex);
            prefs = locationPrefs[icon.uniqueIdentifier];
        }

        NSUInteger writeIndex = prefs.index;
        SBHIconGridSize writeSize = prefs.gridSize;
    

        int limit = 0;
        while (!checkValidIndexForIconSize(info, writeSize, writeIndex)) {
            needsRefresh = YES;
            //adding a limit just in case it can't find a spot
            if (limit > 150) {
                writeIndex = 0;
                break;
            }

            writeIndex += 1;
            if (writeIndex >= info.gridSize.columns * info.gridSize.rows) {
                //wrap back around
                writeIndex = findFirstOpenIndexInListStartingAt(iconList, info.gridSize, 0);
            }

            limit++;
        }
        
        //only save to location prefs if we have nothing in dragged
        if ([draggedIcons count] == 0) {
            prefs.index = writeIndex;
            prefs.ogIndex = writeIndex;
        }

        NSMutableArray <NSNumber *> *writeIndexList = [NSMutableArray new];

        //go through and gra every grid index for the icon, whihc we will save as the specific icon index
        SBIconCoordinate coord = [info coordinateForGridCellIndex:writeIndex];
        for (int j = 0; j < writeSize.rows; j++) {
            for (int k = 0; k < writeSize.columns; k++) {
                SBIconCoordinate tempCoord;
                tempCoord.column = coord.column + k;
                tempCoord.row = coord.row + j;
                [writeIndexList addObject:[NSNumber numberWithUnsignedLongLong:[info gridCellIndexForCoordinate:tempCoord]]];
            }
        }

        //convert the index in the icon list(ordered by priority) to the actual list that is saved on the SBIconListModel instance
        int realIdx = [staticIconList indexOfObject:icon];

        // write locations to the SBIconGridCellInfo
        for (int k = 0; k < [writeIndexList count]; k++) {
            [info setIconIndex:realIdx forGridCellIndex:(writeIndexList[k]).unsignedIntegerValue];
        }
        [info setGridCellIndex:writeIndex forIconIndex:realIdx];
    }

    //if we need to sort, sort and redraw
    if (shouldRedrawList) {
        reorderIconListBasedOnCustomIndex(iconList, info.gridSize.columns * info.gridSize.rows); 
        shouldRedrawList = NO;
        return patchGridCellInfoForIconList(iconList, info, model);
    }
    
    return staticIconList;
}

//used to calculate the grid cell index for a point and icon size
//note: this function always returns the index for the top left corner of an icon
long long calculateGridCellIndexForPoint(CGPoint point, CGRect workingSize, SBHIconGridSize workingGridSize, SBHIconGridSize indexOffset, SBHIconGridSize iconSize) {
    NSUInteger tempIdx = 0;
    float iconWidth = (workingSize.size.width / workingGridSize.columns);
    float iconHeight = (workingSize.size.height / workingGridSize.rows);

    //get the column index
    tempIdx += (NSUInteger)((point.x-workingSize.origin.x) / iconWidth);
    //add the indexes of all the rows before it
    tempIdx += workingGridSize.columns * (NSUInteger)((point.y-workingSize.origin.y) / iconHeight);

    //factor in offset
    tempIdx -= indexOffset.columns;
    tempIdx -= indexOffset.rows * workingGridSize.columns;


    //check the end of the icon, and make sure it is still in bounds
    NSUInteger endOfIconIdx = tempIdx + (iconSize.columns-1) + ((iconSize.rows-1) * workingGridSize.columns);
    if (tempIdx < workingGridSize.columns * workingGridSize.rows && endOfIconIdx < workingGridSize.columns * workingGridSize.rows) {
        return tempIdx;
    }

    return proposedIndex;
}