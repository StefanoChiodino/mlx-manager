# Preset Table Buttons - Proposal

## Summary

The preset table's Add (+) and Remove (−) buttons are hidden or inaccessible when the settings window opens. Users cannot add or remove presets because the buttons are not visible or clickable.

## Impact

- Users cannot manage presets (add new presets, remove existing ones)
- Settings table is partially broken
- Poor user experience for preset management

## Root Cause

The "Set Up Environment" NSBox is positioned in a way that covers or overlaps with the preset table's row buttons (+ and −), making them inaccessible.

## Acceptance Criteria

- Preset table displays all rows when window opens
- Add (+) button is visible and clickable
- Remove (−) button is visible and clickable
- No UI elements overlap the buttons
