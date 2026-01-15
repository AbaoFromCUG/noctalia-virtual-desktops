
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

ColumnLayout {
  id: root
  // Plugin API (injected by the settings dialog system)
  //
  property var pluginApi: null
  spacing: Style.marginM


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
    let settings = pluginApi?.pluginSettings ?? pluginApi?.manifest?.metadata?.defaultSetting
    settings = Object.assign({}, defaultSettings, settings);
    return settings
  }

  property string valueLabelMode: widgetSettings.labelMode
  property bool valuehideUnpopulated: widgetSettings.hideUnpopulated
  property bool valueFollowFocusedScreen: widgetSettings.followFocusedScreen 
  property int valueCharacterCount: widgetSettings.characterCount

  // Grouped mode settings
  property bool valueShowApplications: widgetSettings.showApplications
  property bool valueShowLabelsOnlyWhenPopulated: widgetSettings.showLabelsOnlyWhenPopulated
  property bool valueColorizeIcons: widgetSettings.colorizeIcons
  property real valueUnfocusedIconsOpacity: widgetSettings.unfocusedIconsOpacity
  property real valueGroupedBorderOpacity: widgetSettings.groupedBorderOpacity
  property bool valueEnableScrollWheel: widgetSettings.enableScrollWheel
  property real valueIconScale: widgetSettings.iconScale

  function saveSettings() {
    var settings = Object.assign({}, pluginApi.pluginSettings ?? pluginApi?.manifest?.metadata?.defaultSetting ?? {});
    pluginApi.pluginSettings.labelMode = valueLabelMode;
    pluginApi.pluginSettings.hideUnpopulated = valuehideUnpopulated;
    pluginApi.pluginSettings.characterCount = valueCharacterCount;
    pluginApi.pluginSettings.followFocusedScreen = valueFollowFocusedScreen;
    pluginApi.pluginSettings.showApplications = valueShowApplications;
    pluginApi.pluginSettings.showLabelsOnlyWhenPopulated = valueShowLabelsOnlyWhenPopulated;
    pluginApi.pluginSettings.colorizeIcons = valueColorizeIcons;
    pluginApi.pluginSettings.unfocusedIconsOpacity = valueUnfocusedIconsOpacity;
    pluginApi.pluginSettings.groupedBorderOpacity = valueGroupedBorderOpacity;
    pluginApi.pluginSettings.enableScrollWheel = valueEnableScrollWheel;
    pluginApi.pluginSettings.iconScale = valueIconScale;
    Logger.i("VirtualDesktops", "Settings saved successfully")
    pluginApi.saveSettings()
  }

  NComboBox {
    id: labelModeCombo
    label: pluginApi?.tr("bar.label-mode-label")
    description: pluginApi?.tr("bar.label-mode-description")
    model: [
      {
        "key": "none",
        "name": I18n.tr("common.none")
      },
      {
        "key": "index",
        "name": I18n.tr("options.workspace-labels.index")
      },
      {
        "key": "name",
        "name": I18n.tr("options.workspace-labels.name")
      },
      {
        "key": "index+name",
        "name": I18n.tr("options.workspace-labels.index-and-name")
      }
    ]
    currentKey: pluginApi?.pluginSettings?.labelMode?? ""
    onSelected: key => valueLabelMode = key
    minimumWidth: 200
  }

  NSpinBox {
    label: pluginApi?.tr("bar.character-count-label")
    description: pluginApi?.tr("bar.character-count-description")
    from: 1
    to: 10
    value: valueCharacterCount
    onValueChanged: valueCharacterCount = value
    visible: valueLabelMode === "name" || valueLabelMode === "index+name"
  }

  NToggle {
    label: pluginApi?.tr("bar.hide-unpopulated-label")
    description: pluginApi?.tr("bar.hide-unpopulated-description")
    checked: valuehideUnpopulated
    onToggled: checked => valuehideUnpopulated = checked
  }

  NToggle {
    label: pluginApi?.tr("bar.show-labels-only-when-populated-label")
    description: pluginApi?.tr("bar.show-labels-only-when-populated-description")
    checked: valueShowLabelsOnlyWhenPopulated
    onToggled: checked => valueShowLabelsOnlyWhenPopulated = checked
  }

  NToggle {
    label: pluginApi?.tr("bar.follow-focused-screen-label")
    description: pluginApi?.tr("bar.follow-focused-screen-description")
    checked: valueFollowFocusedScreen
    onToggled: checked => valueFollowFocusedScreen = checked
  }

  NToggle {
    label: pluginApi?.tr("bar.enable-scrollwheel-label")
    description: pluginApi?.tr("bar.enable-scrollwheel-description")
    checked: valueEnableScrollWheel
    onToggled: checked => valueEnableScrollWheel = checked
  }

  NDivider {
    Layout.fillWidth: true
  }

  NToggle {
    label: pluginApi?.tr("bar.show-applications-label")
    description: pluginApi?.tr("bar.show-applications-description")
    checked: valueShowApplications
    onToggled: checked => valueShowApplications = checked
  }

  NToggle {
    label: I18n.tr("bar.tray.colorize-icons-label")
    description: I18n.tr("bar.active-window.colorize-icons-description")
    checked: valueColorizeIcons
    onToggled: checked => valueColorizeIcons = checked
    visible: valueShowApplications
  }

  NValueSlider {
    label: pluginApi?.tr("bar.unfocused-icons-opacity-label")
    description: pluginApi?.tr("bar.unfocused-icons-opacity-description")
    from: 0
    to: 1
    stepSize: 0.01
    value: valueUnfocusedIconsOpacity
    onMoved: value => valueUnfocusedIconsOpacity = value
    text: Math.floor(valueUnfocusedIconsOpacity * 100) + "%"
    visible: valueShowApplications
  }

  NValueSlider {
    label: pluginApi?.tr("bar.grouped-border-opacity-label")
    description: pluginApi?.tr("bar.grouped-border-opacity-description")
    from: 0
    to: 1
    stepSize: 0.01
    value: valueGroupedBorderOpacity
    onMoved: value => valueGroupedBorderOpacity = value
    text: Math.floor(valueGroupedBorderOpacity * 100) + "%"
    visible: valueShowApplications
  }

  NValueSlider {
    label: I18n.tr("bar.taskbar.icon-scale-label")
    description: I18n.tr("bar.taskbar.icon-scale-description")
    from: 0.5
    to: 1
    stepSize: 0.01
    value: valueIconScale
    onMoved: value => valueIconScale = value
    text: Math.round(valueIconScale * 100) + "%"
    visible: valueShowApplications
  }
}
