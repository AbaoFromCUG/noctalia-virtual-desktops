
import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Layouts
import QtQuick.Window
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import Quickshell.Hyprland
import qs.Commons
import qs.Modules.Bar.Extras
import qs.Services.Compositor
import qs.Services.UI
import qs.Widgets


Item {
  id: root


  // Widget properties passed from Bar.qml for per-instance settings
  property var pluginApi: null
  property ShellScreen screen
  property string widgetId: ""
  property string section: ""
  property int sectionWidgetIndex: -1
  property int sectionWidgetsCount: 0

  property var widgetSettings: {
    let defaultSettings = {
        "characterCount": 10,
        "colorizeIcons": false,
        "enableScrollWheel": true,
        "followFocusedScreen": false,
        "groupedBorderOpacity": 1,
        "hideUnpopulated": true,
        "iconScale": 1,
        "labelMode": "index",
        "showApplications": false,
        "showLabelsOnlyWhenPopulated": true,
        "unfocusedIconsOpacity": 1
    };
    if (section && sectionWidgetIndex >= 0) {
      let settings = pluginApi?.pluginSettings ?? pluginApi?.manifest?.metadata?.defaultSetting
      settings = Object.assign({}, defaultSettings, settings);
      return settings
    }
    return defaultSettings;
  }

  readonly property string barPosition: Settings.data.bar.position
  readonly property bool isVertical: barPosition === "left" || barPosition === "right"
  readonly property real baseDimensionRatio: 0.65 * (widgetSettings.labelMode === "none" ? 0.75 : 1)

  readonly property string labelMode: widgetSettings.labelMode
  readonly property bool hasLabel: (labelMode !== "none")
  readonly property bool hideUnpopulated: widgetSettings.hideUnpopulated
  readonly property bool followFocusedScreen: widgetSettings.followFocusedScreen
  readonly property int characterCount: isVertical ? 2 : widgetSettings.characterCount
  // Grouped mode (show applications) settings
  readonly property bool showApplications: widgetSettings.showApplications
  readonly property bool showLabelsOnlyWhenPopulated: widgetSettings.showLabelsOnlyWhenPopulated
  readonly property bool colorizeIcons: widgetSettings.colorizeIcons
  readonly property real unfocusedIconsOpacity: widgetSettings.unfocusedIconsOpacity
  readonly property real groupedBorderOpacity: widgetSettings.groupedBorderOpacity
  readonly property bool enableScrollWheel: widgetSettings.enableScrollWheel
  readonly property real iconScale: widgetSettings.iconScale

  // Only for grouped mode / show apps
  readonly property int baseItemSize: Style.toOdd(Style.capsuleHeight * 0.8)
  readonly property int iconSize: Style.toOdd(baseItemSize * iconScale)
  readonly property real textRatio: 0.50

  // Context menu state for grouped mode - store IDs instead of object references to avoid stale references
  property string selectedWindowId: ""
  property string selectedAppId: ""

  // Helper to get the current window object from ID
  function getSelectedWindow() {
    if (!selectedWindowId)
      return null;
    for (var i = 0; i < virtualDesktops.count; i++) {
      var ws = virtualDesktops.get(i);
      if (ws && ws.windows) {
        for (var j = 0; j < ws.windows.count; j++) {
          var win = ws.windows.get(j);
          // Using loose equality on purpose (==)
          if (win && (win.id == selectedWindowId || win.address == selectedWindowId)) {
            return win;
          }
        }
      }
    }
    return null;
  }

  property bool isDestroying: false
  property bool hovered: false

  // Revision counter to force icon re-evaluation
  property int iconRevision: 0

  property ListModel virtualDesktops: ListModel {}
  property real masterProgress: 0.0
  property bool effectsActive: false
  property color effectColor: Color.mPrimary

  property int horizontalPadding: Style.marginS
  property int spacingBetweenPills: Style.marginXS

  // Wheel scroll handling
  property int wheelAccumulatedDelta: 0
  property bool wheelCooldown: false

  signal desktopChanged(int desktopId, color accentColor)

  implicitWidth: showApplications ? (isVertical ? groupedGrid.implicitWidth : Math.round(groupedGrid.implicitWidth + horizontalPadding * hasLabel)) : (isVertical ? Style.barHeight : computeWidth())
  implicitHeight: showApplications ? (isVertical ? Math.round(groupedGrid.implicitHeight + horizontalPadding * 0.6 * hasLabel) : Style.barHeight) : (isVertical ? computeHeight() : Style.barHeight)

  function getVirtualDesktopWidth(ws) {
    const d = Math.round(Style.capsuleHeight * root.baseDimensionRatio);
    const factor = ws.isActive ? 2.2 : 1;

    // Don't calculate text width if labels are off
    if (labelMode === "none") {
      return Math.round(d * factor);
    }

    var displayText = ws.idx.toString();

    if (ws.name && ws.name.length > 0) {
      if (root.labelMode === "name") {
        displayText = ws.name.substring(0, characterCount);
      } else if (root.labelMode === "index+name") {
        displayText = ws.idx.toString() + " " + ws.name.substring(0, characterCount);
      }
    }

    const textWidth = displayText.length * (d * 0.4); // Approximate width per character
    const padding = d * 0.6;
    return Style.toOdd(Math.max(d * factor, textWidth + padding));
  }

  function getVirtualDesktopHeight(ws) {
    const d = Math.round(Style.capsuleHeight * root.baseDimensionRatio);
    const factor = ws.isActive ? 2.2 : 1;
    return Style.toOdd(d * factor);
  }

  function computeWidth() {
    let total = 0;
    for (var i = 0; i < virtualDesktops.count; i++) {
      const ws = virtualDesktops.get(i);
      total += getVirtualDesktopWidth(ws);
    }
    total += Math.max(virtualDesktops.count - 1, 0) * spacingBetweenPills;
    total += horizontalPadding * 2;
    return Style.toOdd(total);
  }

  function computeHeight() {
    let total = 0;
    for (var i = 0; i < virtualDesktops.count; i++) {
      const ws = virtualDesktops.get(i);
      total += getVirtualDesktopHeight(ws);
    }
    total += Math.max(virtualDesktops.count - 1, 0) * spacingBetweenPills;
    total += horizontalPadding * 2;
    return Style.toOdd(total);
  }

  function getFocusedLocalIndex() {
    for (var i = 0; i < virtualDesktops.count; i++) {
      if (virtualDesktops.get(i).isFocused === true)
        return i;
    }
    return -1;
  }

  function switchByOffset(offset) {
    if (virtualDesktops.count === 0)
      return;
    var current = getFocusedLocalIndex();
    if (current < 0)
      current = 0;
    var next = (current + offset) % virtualDesktops.count;
    if (next < 0)
      next = virtualDesktops.count - 1;
    const ws = virtualDesktops.get(next);
    if (ws && ws.idx !== undefined)
      Hyprland.dispatch(`vdesk ${ws.id}`)
  }

  // Helper function to normalize app IDs for case-insensitive matching
  function normalizeAppId(appId) {
    if (!appId || typeof appId !== 'string')
      return "";
    return appId.toLowerCase().trim();
  }

  // Helper function to check if an app is pinned
  function isAppPinned(appId) {
    if (!appId)
      return false;
    const pinnedApps = Settings.data.dock.pinnedApps || [];
    const normalizedId = normalizeAppId(appId);
    return pinnedApps.some(pinnedId => normalizeAppId(pinnedId) === normalizedId);
  }

  // Helper function to toggle app pin/unpin
  function toggleAppPin(appId) {
    if (!appId)
      return;

    const normalizedId = normalizeAppId(appId);
    let pinnedApps = (Settings.data.dock.pinnedApps || []).slice();

    const existingIndex = pinnedApps.findIndex(pinnedId => normalizeAppId(pinnedId) === normalizedId);
    const isPinned = existingIndex >= 0;

    if (isPinned) {
      pinnedApps.splice(existingIndex, 1);
    } else {
      pinnedApps.push(appId);
    }

    Settings.data.dock.pinnedApps = pinnedApps;
  }

  Component.onCompleted: {
    refreshVirtualDesktops();
  }

  Component.onDestruction: {
    root.isDestroying = true;
  }

  onScreenChanged: refreshVirtualDesktops()
  onHideUnpopulatedChanged: refreshVirtualDesktops()

  Connections {
    target: CompositorService
    function onWorkspacesChanged() {
      refreshVirtualDesktops();
      root.triggerUnifiedWave();
    }
    function onWindowListChanged() {
      if (showApplications || showLabelsOnlyWhenPopulated) {
        refreshVirtualDesktops();
      }
    }
    function onActiveWindowChanged() {
      if (showApplications) {
        refreshVirtualDesktops();
      }
    }
  }

  Process {
    id: hyprlandVDProcess
    running: false
    command: ["hyprctl", "printstate", "-j"]

    property string accumulatedOutput: ""

    stdout: SplitParser {
      onRead: function (line) {
        // Accumulate lines instead of parsing each one
        hyprlandVDProcess.accumulatedOutput += line;
      }
    }

    onExited: function (exitCode) {
      if (exitCode !== 0 || !accumulatedOutput) {
        accumulatedOutput = "";
        return;
      }

      try {
        virtualDesktops.clear();
        const layoutState = JSON.parse(accumulatedOutput);
        layoutState.sort((a, b) => a.id - b.id);
        for (let i =0; i < layoutState.length; i++) {

            let vd = layoutState[i];
            if (hideUnpopulated && !vd.populated) {
              // Filter out unpopulated desktops
              continue;
            }

            let windows = []
            for (let ws of vd.workspaces) {
                for (let win of CompositorService.getWindowsForWorkspace(ws)) {
                    windows.push(win);
                }
            }
            var desktopData = {
                id: vd.id,
                idx: vd.id,
                name: vd.name,
                title: vd.name,
                isFocused: vd.focused,
                focused: vd.focused,
                populated: vd.populated,
                isActive: vd.populated,
                isOccupied: vd.populated,
                workspaces: vd.workspaces,
                windowCount: vd.windows,
                windows: windows,
            }
          virtualDesktops.append(desktopData);
        }
      } catch (e) {
        Logger.e("VirtualDesktops", "Failed to parse virtual desktops:", e);
      } finally {
        // Clear accumulated output for next query
        accumulatedOutput = "";
      }

      updateDesktopFocus();
    }
  }



  // Refresh icons when DesktopEntries becomes available
  Connections {
    target: DesktopEntries.applications
    function onValuesChanged() {
      root.iconRevision++;
    }
  }

  function refreshVirtualDesktops() {
    hyprlandVDProcess.running =true
  }

  function triggerUnifiedWave() {
    effectColor = Color.mPrimary;
    masterAnimation.restart();
  }

  function updateDesktopFocus() {
    for (var i = 0; i < virtualDesktops.count; i++) {
      const ws = virtualDesktops.get(i);
      if (ws.isFocused === true) {
        root.desktopChanged(ws.id, Color.mPrimary);
        break;
      }
    }
  }

  SequentialAnimation {
    id: masterAnimation
    PropertyAction {
      target: root
      property: "effectsActive"
      value: true
    }
    NumberAnimation {
      target: root
      property: "masterProgress"
      from: 0.0
      to: 1.0
      duration: Style.animationSlow * 2
      easing.type: Easing.OutQuint
    }
    PropertyAction {
      target: root
      property: "effectsActive"
      value: false
    }
    PropertyAction {
      target: root
      property: "masterProgress"
      value: 0.0
    }
  }

  NPopupContextMenu {
    id: contextMenu

    model: {
      var items = [];
      if (root.selectedWindowId) {
        // Focus item
        items.push({
                     "label": I18n.tr("common.focus"),
                     "action": "focus",
                     "icon": "eye"
                   });

        // Pin/Unpin item
        const isPinned = root.isAppPinned(root.selectedAppId);
        items.push({
                     "label": !isPinned ? I18n.tr("common.pin") : I18n.tr("common.unpin"),
                     "action": "pin",
                     "icon": !isPinned ? "pin" : "pinned-off"
                   });

        // Close item
        items.push({
                     "label": I18n.tr("common.close"),
                     "action": "close",
                     "icon": "x"
                   });

        // Add desktop entry actions
        if (typeof DesktopEntries !== 'undefined' && DesktopEntries.byId && root.selectedAppId) {
          const entry = (DesktopEntries.heuristicLookup) ? DesktopEntries.heuristicLookup(root.selectedAppId) : DesktopEntries.byId(root.selectedAppId);
          if (entry != null && entry.actions) {
            entry.actions.forEach(function (action) {
              items.push({
                           "label": action.name,
                           "action": "desktop-action-" + action.name,
                           "icon": "chevron-right",
                           "desktopAction": action
                         });
            });
          }
        }
      }
      items.push({
                   "label": I18n.tr("actions.widget-settings"),
                   "action": "widget-settings",
                   "icon": "settings"
                 });
      return items;
    }

    onTriggered: (action, item) => {
                   var popupMenuWindow = PanelService.getPopupMenuWindow(screen);
                   if (popupMenuWindow) {
                     popupMenuWindow.close();
                   }

                   const selectedWindow = root.getSelectedWindow();

                   if (action === "focus" && selectedWindow) {
                     CompositorService.focusWindow(selectedWindow);
                   } else if (action === "pin" && selectedAppId) {
                     root.toggleAppPin(selectedAppId);
                   } else if (action === "close" && selectedWindow) {
                     CompositorService.closeWindow(selectedWindow);
                   } else if (action === "widget-settings") {
                     BarService.openWidgetSettings(screen, section, sectionWidgetIndex, widgetId, widgetSettings);
                   } else if (action.startsWith("desktop-action-") && item && item.desktopAction) {
                     if (item.desktopAction.command && item.desktopAction.command.length > 0) {
                       Quickshell.execDetached(item.desktopAction.command);
                     } else if (item.desktopAction.execute) {
                       item.desktopAction.execute();
                     }
                   }
                   selectedWindowId = "";
                   selectedAppId = "";
                 }
  }

  Rectangle {
    id: virtualDesktopBackground
    visible: !showApplications
    width: isVertical ? Style.capsuleHeight : parent.width
    height: isVertical ? parent.height : Style.capsuleHeight
    radius: Style.radiusM
    color: Style.capsuleColor
    border.color: Style.capsuleBorderColor
    border.width: Style.capsuleBorderWidth

    x: isVertical ? Style.pixelAlignCenter(parent.width, width) : 0
    y: isVertical ? 0 : Style.pixelAlignCenter(parent.height, height)

    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.RightButton
      onClicked: mouse => {
                   if (mouse.button === Qt.RightButton) {
                     var popupMenuWindow = PanelService.getPopupMenuWindow(screen);
                     if (popupMenuWindow) {
                       popupMenuWindow.showContextMenu(contextMenu);
                       contextMenu.openAtItem(virtualDesktopBackground, screen);
                     }
                   }
                 }
    }
  }

  // Debounce timer for wheel interactions
  Timer {
    id: wheelDebounce
    interval: 150
    repeat: false
    onTriggered: {
      root.wheelCooldown = false;
      root.wheelAccumulatedDelta = 0;
    }
  }

  // Scroll to switch virtual desktops
  WheelHandler {
    id: wheelHandler
    target: root
    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
    enabled: root.enableScrollWheel
    onWheel: function (event) {
      if (root.wheelCooldown)
        return;
      // Prefer vertical delta, fall back to horizontal if needed
      var dy = event.angleDelta.y;
      var dx = event.angleDelta.x;
      var useDy = Math.abs(dy) >= Math.abs(dx);
      var delta = useDy ? dy : dx;
      // One notch is typically 120
      root.wheelAccumulatedDelta += delta;
      var step = 120;
      if (Math.abs(root.wheelAccumulatedDelta) >= step) {
        var direction = root.wheelAccumulatedDelta > 0 ? -1 : 1;
        // For vertical layout, natural mapping: wheel up -> previous, down -> next (already handled by sign)
        // For horizontal layout, same mapping using vertical wheel
        root.switchByOffset(direction);
        root.wheelCooldown = true;
        wheelDebounce.restart();
        root.wheelAccumulatedDelta = 0;
        event.accepted = true;
      }
    }
  }

  // Horizontal layout for top/bottom bars
  Row {
    id: pillRow
    spacing: spacingBetweenPills
    x: horizontalPadding
    y: virtualDesktopBackground.y + Style.pixelAlignCenter(virtualDesktopBackground.height, height)
    visible: !isVertical && !showApplications

    Repeater {
      id: desktopRepeaterHorizontal
      model: virtualDesktops
      Item {
        id: virtualDesktopPillContainer
        width: root.getVirtualDesktopWidth(model)
        height: Style.toOdd(Style.capsuleHeight * root.baseDimensionRatio)

        Rectangle {
          id: pill
          anchors.fill: parent

          Loader {
            active: (labelMode !== "none") && (!root.showLabelsOnlyWhenPopulated || model.isOccupied || model.isFocused)
            sourceComponent: Component {
              NText {
                x: Style.pixelAlignCenter(pill.width, width)
                y: Style.pixelAlignCenter(pill.height, height)
                text: {
                  if (model.name && model.name.length > 0) {
                    if (root.labelMode === "name") {
                      return model.name.substring(0, characterCount);
                    }
                    if (root.labelMode === "index+name") {
                      return (model.idx.toString() + " " + model.name.substring(0, characterCount));
                    }
                  }
                  return model.idx.toString();
                }
                family: Settings.data.ui.fontFixed
                pointSize: virtualDesktopPillContainer.height * root.textRatio
                applyUiScale: false
                font.capitalization: Font.AllUppercase
                font.weight: Style.fontWeightBold
                wrapMode: Text.Wrap
                color: {
                  if (model.isFocused)
                    return Color.mOnPrimary;
                  if (model.isUrgent)
                    return Color.mOnError;
                  if (model.isOccupied)
                    return Color.mOnSecondary;

                  return Color.mOnSecondary;
                }
              }
            }
          }

          radius: Style.radiusM
          color: {
            if (model.isFocused)
              return Color.mPrimary;
            if (model.isUrgent)
              return Color.mError;
            if (model.isOccupied)
              return Color.mSecondary;

            return Qt.alpha(Color.mSecondary, 0.3);
          }
          z: 0

          MouseArea {
            id: pillMouseArea
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              Hyprland.dispatch(`vdesk ${model.id}`)
            }
            hoverEnabled: true
          }
          // Material 3-inspired smooth animation for width, height, scale, color, opacity, and radius
          Behavior on width {
            NumberAnimation {
              duration: Style.animationNormal
              easing.type: Easing.OutBack
            }
          }
          Behavior on height {
            NumberAnimation {
              duration: Style.animationNormal
              easing.type: Easing.OutBack
            }
          }
          Behavior on scale {
            NumberAnimation {
              duration: Style.animationNormal
              easing.type: Easing.OutBack
            }
          }
          Behavior on color {
            ColorAnimation {
              duration: Style.animationFast
              easing.type: Easing.InOutCubic
            }
          }
          Behavior on opacity {
            NumberAnimation {
              duration: Style.animationFast
              easing.type: Easing.InOutCubic
            }
          }
          Behavior on radius {
            NumberAnimation {
              duration: Style.animationNormal
              easing.type: Easing.OutBack
            }
          }
        }

        Behavior on width {
          NumberAnimation {
            duration: Style.animationNormal
            easing.type: Easing.OutBack
          }
        }
        Behavior on height {
          NumberAnimation {
            duration: Style.animationNormal
            easing.type: Easing.OutBack
          }
        }
        // Burst effect overlay for focused pill (smaller outline)
        Rectangle {
          id: pillBurst
          anchors.centerIn: virtualDesktopPillContainer
          width: virtualDesktopPillContainer.width + 18 * root.masterProgress * scale
          height: virtualDesktopPillContainer.height + 18 * root.masterProgress * scale
          radius: width / 2
          color: "transparent"
          border.color: root.effectColor
          border.width: Math.max(1, Math.round((2 + 6 * (1.0 - root.masterProgress))))
          opacity: root.effectsActive && model.isFocused ? (1.0 - root.masterProgress) * 0.7 : 0
          visible: root.effectsActive && model.isFocused
          z: 1
        }
      }
    }
  }

  // Vertical layout for left/right bars
  Column {
    id: pillColumn
    spacing: spacingBetweenPills
    x: virtualDesktopBackground.x + Style.pixelAlignCenter(virtualDesktopBackground.width, width)
    y: horizontalPadding
    visible: isVertical && !showApplications

    Repeater {
      id: desktopRepeaterVertical
      model: virtualDesktops
      Item {
        id: virtualDesktopPillContainerVertical
        width: Style.toOdd(Style.capsuleHeight * root.baseDimensionRatio)
        height: root.getVirtualDesktopHeight(model)

        Rectangle {
          id: pillVertical
          anchors.fill: parent

          Loader {
            active: (labelMode !== "none") && (!root.showLabelsOnlyWhenPopulated || model.isOccupied || model.isFocused)
            sourceComponent: Component {
              NText {
                x: Style.pixelAlignCenter(pillVertical.width, width)
                y: Style.pixelAlignCenter(pillVertical.height, height)
                text: {
                  if (model.name && model.name.length > 0) {
                    if (root.labelMode === "name") {
                      return model.name.substring(0, characterCount);
                    }
                    if (root.labelMode === "index+name") {
                      return (model.idx.toString() + model.name.substring(0, characterCount));
                    }
                  }
                  return model.idx.toString();
                }
                family: Settings.data.ui.fontFixed
                pointSize: virtualDesktopPillContainerVertical.width * root.textRatio
                applyUiScale: false
                font.capitalization: Font.AllUppercase
                font.weight: Style.fontWeightBold
                wrapMode: Text.Wrap
                color: {
                  if (model.isFocused)
                    return Color.mOnPrimary;
                  if (model.isUrgent)
                    return Color.mOnError;
                  if (model.isOccupied)
                    return Color.mOnSecondary;

                  return Color.mOnSecondary;
                }
              }
            }
          }

          radius: Style.radiusM
          color: {
            if (model.isFocused)
              return Color.mPrimary;
            if (model.isUrgent)
              return Color.mError;
            if (model.isOccupied)
              return Color.mSecondary;

            return Qt.alpha(Color.mSecondary, 0.3);
          }
          z: 0

          MouseArea {
            id: pillMouseAreaVertical
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              Hyprland.dispatch(`vdesk ${model.id}`)
            }
            hoverEnabled: true
          }
          // Material 3-inspired smooth animation for width, height, scale, color, opacity, and radius
          Behavior on width {
            NumberAnimation {
              duration: Style.animationNormal
              easing.type: Easing.OutBack
            }
          }
          Behavior on height {
            NumberAnimation {
              duration: Style.animationNormal
              easing.type: Easing.OutBack
            }
          }
          Behavior on scale {
            NumberAnimation {
              duration: Style.animationNormal
              easing.type: Easing.OutBack
            }
          }
          Behavior on color {
            ColorAnimation {
              duration: Style.animationFast
              easing.type: Easing.InOutCubic
            }
          }
          Behavior on opacity {
            NumberAnimation {
              duration: Style.animationFast
              easing.type: Easing.InOutCubic
            }
          }
          Behavior on radius {
            NumberAnimation {
              duration: Style.animationNormal
              easing.type: Easing.OutBack
            }
          }
        }

        Behavior on width {
          NumberAnimation {
            duration: Style.animationNormal
            easing.type: Easing.OutBack
          }
        }
        Behavior on height {
          NumberAnimation {
            duration: Style.animationNormal
            easing.type: Easing.OutBack
          }
        }
        // Burst effect overlay for focused pill (smaller outline)
        Rectangle {
          id: pillBurstVertical
          anchors.centerIn: virtualDesktopPillContainerVertical
          width: virtualDesktopPillContainerVertical.width + 18 * root.masterProgress * scale
          height: virtualDesktopPillContainerVertical.height + 18 * root.masterProgress * scale
          radius: width / 2
          color: "transparent"
          border.color: root.effectColor
          border.width: Math.max(1, Math.round((2 + 6 * (1.0 - root.masterProgress))))
          opacity: root.effectsActive && model.isFocused ? (1.0 - root.masterProgress) * 0.7 : 0
          visible: root.effectsActive && model.isFocused
          z: 1
        }
      }
    }
  }

  // ========================================
  // Grouped mode (showApplications = true)
  // ========================================

  Component {
    id: groupedWorkspaceDelegate

    Rectangle {
      id: groupedContainer

      required property var model
      property var virtualDesktopModel: model
      property bool hasWindows: (virtualDesktopModel?.windows?.count ?? 0) > 0

      width: Style.toOdd((hasWindows ? groupedIconsFlow.implicitWidth : root.iconSize) + (root.isVertical ? (root.baseItemSize - root.iconSize + Style.marginXS) : Style.marginXL))
      height: Style.toOdd((hasWindows ? groupedIconsFlow.implicitHeight : root.iconSize) + (root.isVertical ? Style.marginL : (root.baseItemSize - root.iconSize + Style.marginXS)))
      color: Style.capsuleColor
      radius: Style.radiusS
      border.color: Settings.data.bar.showOutline ? Style.capsuleBorderColor : Qt.alpha((virtualDesktopModel.isFocused ? Color.mPrimary : Color.mOutline), root.groupedBorderOpacity)
      border.width: Style.borderS

      MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        enabled: !groupedContainer.hasWindows
        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        preventStealing: true
        onPressed: mouse => {
                     if (mouse.button === Qt.LeftButton) {
                        Hyprland.dispatch(`vdesk ${groupedContainer.virtualDesktopModel.id}`)
                     }
                   }
        onReleased: mouse => {
                      if (mouse.button === Qt.RightButton) {
                        mouse.accepted = true;
                        TooltipService.hide();
                        root.selectedWindowId = "";
                        root.selectedAppId = "";
                        openGroupedContextMenu(groupedContainer);
                      }
                    }
      }

      Flow {
        id: groupedIconsFlow

        x: Style.pixelAlignCenter(parent.width, width)
        y: Style.pixelAlignCenter(parent.height, height)
        spacing: 2
        flow: root.isVertical ? Flow.TopToBottom : Flow.LeftToRight

        Repeater {
          model: groupedContainer.virtualDesktopModel.windows

          delegate: Item {
            id: groupedTaskbarItem

            property bool itemHovered: false

            width: root.iconSize
            height: root.iconSize

            IconImage {
              id: groupedAppIcon

              width: parent.width
              height: parent.height
              source: {
                root.iconRevision; // Force re-evaluation when revision changes
                return ThemeIcons.iconForAppId(model.appId?.toLowerCase());
              }
              smooth: true
              asynchronous: true
              opacity: model.isFocused ? Style.opacityFull : unfocusedIconsOpacity
              layer.enabled: root.colorizeIcons && !model.isFocused

              Rectangle {
                id: groupedFocusIndicator
                visible: model.isFocused
                anchors.bottomMargin: -2
                anchors.bottom: parent.bottom
                anchors.horizontalCenter: parent.horizontalCenter
                width: Style.toOdd(root.iconSize * 0.25)
                height: 4
                color: Color.mPrimary
                radius: Math.min(Style.radiusXXS, width / 2)
              }

              layer.effect: ShaderEffect {
                property color targetColor: Settings.data.colorSchemes.darkMode ? Color.mOnSurface : Color.mSurfaceVariant
                property real colorizeMode: 0
                fragmentShader: Qt.resolvedUrl(Quickshell.shellDir + "/Shaders/qsb/appicon_colorize.frag.qsb")
              }
            }

            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              acceptedButtons: Qt.LeftButton | Qt.RightButton
              preventStealing: true

              onPressed: mouse => {
                           if (!model)
                           return;
                           if (mouse.button === Qt.LeftButton) {
                             Hyprland.dispatch(`vdesk ${groupedContainer.virtualDesktopModel.id}`)
                             CompositorService.focusWindow(model);
                           }
                         }

              onReleased: mouse => {
                            if (!model)
                            return;
                            if (mouse.button === Qt.RightButton) {
                              mouse.accepted = true;
                              TooltipService.hide();
                              root.selectedWindowId = model.id || model.address || "";
                              root.selectedAppId = model.appId;
                              openGroupedContextMenu(groupedTaskbarItem);
                            }
                          }
              onEntered: {
                groupedTaskbarItem.itemHovered = true;
                TooltipService.show(groupedTaskbarItem, model.title || model.appId || "Unknown app.", BarService.getTooltipDirection());
              }
              onExited: {
                groupedTaskbarItem.itemHovered = false;
                TooltipService.hide();
              }
            }
          }
        }
      }

      Item {
        id: groupedDesktopNumberContainer

        visible: root.labelMode !== "none" && (!root.showLabelsOnlyWhenPopulated || groupedContainer.hasWindows || groupedContainer.virtualDesktopModel.isFocused)

        anchors {
          left: parent.left
          top: parent.top
          leftMargin: -Style.fontSizeXS * 0.55
          topMargin: -Style.fontSizeXS * 0.25
        }

        width: Math.max(groupedDesktopNumber.implicitWidth + (Style.marginXS * 2), Style.fontSizeXXS * 2)
        height: Math.max(groupedDesktopNumber.implicitHeight + Style.marginXS, Style.fontSizeXXS * 2)

        Rectangle {
          id: groupedDesktopNumberBackground

          anchors.fill: parent
          radius: Math.min(Style.radiusL, width / 2)

          color: {
            if (groupedContainer.virtualDesktopModel.isFocused)
              return Color.mPrimary;
            if (groupedContainer.virtualDesktopModel.isUrgent)
              return Color.mError;
            if (groupedContainer.hasWindows)
              return Color.mSecondary;

            if (Settings.data.colorSchemes.darkMode) {
              return Qt.darker(Color.mSecondary, 1.5);
            } else {
              return Qt.lighter(Color.mSecondary, 1.5);
            }
          }

          scale: groupedContainer.virtualDesktopModel.isActive ? 1.0 : 0.8

          Behavior on scale {
            NumberAnimation {
              duration: Style.animationNormal
              easing.type: Easing.OutBack
            }
          }

          Behavior on color {
            ColorAnimation {
              duration: Style.animationFast
              easing.type: Easing.InOutCubic
            }
          }
        }

        // Burst effect overlay for focused virtual desktop number
        Rectangle {
          id: groupedDesktopNumberBurst
          anchors.centerIn: groupedDesktopNumberContainer
          width: groupedDesktopNumberContainer.width + 12 * root.masterProgress
          height: groupedDesktopNumberContainer.height + 12 * root.masterProgress
          radius: width / 2
          color: "transparent"
          border.color: root.effectColor
          border.width: Math.max(1, Math.round((2 + 4 * (1.0 - root.masterProgress))))
          opacity: root.effectsActive && groupedContainer.virtualDesktopModel.isFocused ? (1.0 - root.masterProgress) * 0.7 : 0
          visible: root.effectsActive && groupedContainer.virtualDesktopModel.isFocused
          z: 1
        }

        NText {
          id: groupedDesktopNumber

          anchors.centerIn: parent

          text: {
            if (groupedContainer.virtualDesktopModel.name && groupedContainer.virtualDesktopModel.name.length > 0) {
              if (root.labelMode === "name") {
                return groupedContainer.virtualDesktopModel.name.substring(0, root.characterCount);
              }
              if (root.labelMode === "index+name") {
                return (groupedContainer.virtualDesktopModel.idx.toString() + groupedContainer.virtualDesktopModel.name.substring(0, root.characterCount));
              }
            }
            return groupedContainer.virtualDesktopModel.idx.toString();
          }

          family: Settings.data.ui.fontFixed
          font {
            pointSize: Style.barFontSize * 0.75
            weight: Style.fontWeightBold
            capitalization: Font.AllUppercase
          }
          applyUiScale: false

          color: {
            if (groupedContainer.virtualDesktopModel.isFocused)
              return Color.mOnPrimary;
            if (groupedContainer.virtualDesktopModel.isUrgent)
              return Color.mOnError;

            return Color.mOnSecondary;
          }

          Behavior on opacity {
            NumberAnimation {
              duration: Style.animationFast
              easing.type: Easing.InOutCubic
            }
          }
        }

        Behavior on opacity {
          NumberAnimation {
            duration: Style.animationFast
            easing.type: Easing.InOutCubic
          }
        }
      }
    }
  }

  Flow {
    id: groupedGrid
    visible: showApplications

    x: root.isVertical ? Style.pixelAlignCenter(parent.width, width) : Math.round(horizontalPadding * root.hasLabel)
    y: root.isVertical ? Math.round(horizontalPadding * 0.4 * root.hasLabel) : Style.pixelAlignCenter(parent.height, height)

    spacing: Style.marginS
    flow: root.isVertical ? Flow.TopToBottom : Flow.LeftToRight

    Repeater {
      model: showApplications ? virtualDesktops : null
      delegate: groupedWorkspaceDelegate
    }
  }

  function openGroupedContextMenu(item) {
    var popupMenuWindow = PanelService.getPopupMenuWindow(screen);
    if (popupMenuWindow) {
      popupMenuWindow.showContextMenu(contextMenu);
      contextMenu.openAtItem(item, screen);
    }
  }
}
