# Preset Table Buttons - Technical Design

## Current State

In `SettingsWindowController.buildPresetsView()`:

```swift
NSLayoutConstraint.activate([
    scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
    scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
    scrollView.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
    scrollView.bottomAnchor.constraint(equalTo: rowButtons.topAnchor, constant: -4),
    
    rowButtons.leadingAnchor.constraint(equalTo: container.leadingAnchor),
    rowButtons.trailingAnchor.constraint(equalTo: container.trailingAnchor),
    rowButtons.bottomAnchor.constraint(equalTo: envBox.topAnchor, constant: -8),
    
    envBox.leadingAnchor.constraint(equalTo: container.leadingAnchor),
    envBox.trailingAnchor.constraint(equalTo: container.trailingAnchor),
    envBox.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8),
    envBox.heightAnchor.constraint(equalToConstant: 100),
])
```

The NSBox for "Set Up Environment" takes up 100pt height, which should leave space for the buttons. However, the buttons might still be obscured.

## Solution

Adjust the layout to ensure buttons are fully visible:

1. Reduce NSBox height to 90pt
2. Add explicit spacing between envBox and rowButtons
3. Ensure rowButtons are positioned correctly above the NSBox

### Code Change

In `SettingsWindowController.buildPresetsView()` (lines 169-184):

```swift
NSLayoutConstraint.activate([
    scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
    scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
    scrollView.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
    scrollView.bottomAnchor.constraint(equalTo: rowButtons.topAnchor, constant: -4),
    
    rowButtons.leadingAnchor.constraint(equalTo: container.leadingAnchor),
    rowButtons.trailingAnchor.constraint(equalTo: container.trailingAnchor),
    rowButtons.bottomAnchor.constraint(equalTo: envBox.topAnchor, constant: -8),
    
    envBox.leadingAnchor.constraint(equalTo: container.leadingAnchor),
    envBox.trailingAnchor.constraint(equalTo: container.trailingAnchor),
    envBox.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8),
    envBox.heightAnchor.constraint(equalToConstant: 90),  // Reduced from 100
])
```

## Implementation

1. Adjust `envBox.heightAnchor.constraint(equalToConstant:)` to 90pt
2. Test that buttons are visible and accessible

## Testing

- Open settings window
- Verify all preset rows are visible in table
- Verify Add (+) button is visible and clickable
- Verify Remove (−) button is visible and clickable
- Test adding and removing presets
