// Quick settings panel (a GNOME-style aggregate menu for the Omarchy bar):
// connectivity toggles, Do Not Disturb / night light, volume and brightness,
// a small calendar, and power actions. Opened from the bar's menu button.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Bluetooth
import Quickshell.Networking

PanelWindow {
  id: panel

  // Injected by the Variants delegate in shell.qml: the screen to attach to.
  required property var modelData
  // Whether the panel is shown.
  property bool open: false
  // Palette injected from shell.qml (matugen-generated, with a fallback).
  property var theme: ({
    background: "#1e1e2e",
    foreground: "#cdd6f4",
    surface: "#313244",
    accent: "#89b4fa",
    error: "#f38ba8"
  })

  signal dismiss

  screen: modelData
  visible: open
  color: theme.background
  exclusiveZone: 0
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.namespace: "quickshell:quickpanel"
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

  anchors {
    top: true
    right: true
  }
  margins {
    top: 42
    right: 8
  }
  implicitWidth: 360
  implicitHeight: column.implicitHeight + 28

  property bool dnd: false
  property bool nightLight: false
  property date today: new Date()

  function run(args) {
    Quickshell.execDetached(args);
  }

  // Inline components: declared at the document's top level (Qt requires it).
  component ToggleButton: Rectangle {
    property string label
    property bool active
    property var theme
    signal toggled

    Layout.fillWidth: true
    implicitHeight: 34
    radius: 6
    color: active ? theme.accent : theme.surface

    Text {
      anchors.centerIn: parent
      text: parent.label
      color: parent.active ? theme.background : theme.foreground
      font.pixelSize: 12
      font.family: "monospace"
    }

    MouseArea {
      anchors.fill: parent
      onClicked: parent.toggled()
    }
  }

  component ActionButton: Rectangle {
    property string label
    property var theme
    signal activated

    Layout.fillWidth: true
    implicitHeight: 30
    radius: 6
    color: theme.surface

    Text {
      anchors.centerIn: parent
      text: parent.label
      color: theme.foreground
      font.pixelSize: 12
      font.family: "monospace"
    }

    MouseArea {
      anchors.fill: parent
      onClicked: parent.activated()
    }
  }

  ColumnLayout {
    id: column
    anchors {
      left: parent.left
      right: parent.right
      top: parent.top
      margins: 14
    }
    spacing: 10

    // Connectivity
    RowLayout {
      Layout.fillWidth: true
      spacing: 8

      ToggleButton {
        theme: panel.theme
        label: "Wi-Fi"
        active: Networking.wifiEnabled
        onToggled: Networking.wifiEnabled = !Networking.wifiEnabled
      }

      ToggleButton {
        theme: panel.theme
        label: "Bluetooth"
        active: Bluetooth.defaultAdapter !== null && Bluetooth.defaultAdapter.enabled
        onToggled: {
          if (Bluetooth.defaultAdapter !== null)
            Bluetooth.defaultAdapter.enabled = !Bluetooth.defaultAdapter.enabled;
        }
      }
    }

    // Do Not Disturb / night light
    RowLayout {
      Layout.fillWidth: true
      spacing: 8

      ToggleButton {
        theme: panel.theme
        label: "Do not disturb"
        active: panel.dnd
        onToggled: {
          panel.dnd = !panel.dnd;
          panel.run(["sh", "-c",
            "makoctl mode " + (panel.dnd ? "-t do-not-disturb" : "-r do-not-disturb")]);
        }
      }

      ToggleButton {
        theme: panel.theme
        label: "Night light"
        active: panel.nightLight
        onToggled: {
          panel.nightLight = !panel.nightLight;
          panel.run(["pkill", "-USR1", "gammastep"]);
        }
      }
    }

    // Volume
    RowLayout {
      Layout.fillWidth: true
      spacing: 8
      ActionButton {
        theme: panel.theme
        label: "Vol -"
        onActivated: panel.run(["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", "5%-"])
      }
      ActionButton {
        theme: panel.theme
        label: "Mute"
        onActivated: panel.run(["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"])
      }
      ActionButton {
        theme: panel.theme
        label: "Vol +"
        onActivated: panel.run(["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", "5%+"])
      }
    }

    // Brightness
    RowLayout {
      Layout.fillWidth: true
      spacing: 8
      ActionButton {
        theme: panel.theme
        label: "Darker"
        onActivated: panel.run(["brightnessctl", "set", "5%-"])
      }
      ActionButton {
        theme: panel.theme
        label: "Brighter"
        onActivated: panel.run(["brightnessctl", "set", "5%+"])
      }
    }

    // Power profile (power-profiles-daemon, the backend for Plasma's slider)
    RowLayout {
      Layout.fillWidth: true
      spacing: 8
      ActionButton {
        theme: panel.theme
        label: "Saver"
        onActivated: panel.run(["powerprofilesctl", "set", "power-saver"])
      }
      ActionButton {
        theme: panel.theme
        label: "Balanced"
        onActivated: panel.run(["powerprofilesctl", "set", "balanced"])
      }
      ActionButton {
        theme: panel.theme
        label: "Performance"
        onActivated: panel.run(["powerprofilesctl", "set", "performance"])
      }
    }

    // Calendar
    ColumnLayout {
      Layout.fillWidth: true
      spacing: 4

      Text {
        Layout.fillWidth: true
        horizontalAlignment: Text.AlignHCenter
        text: Qt.formatDateTime(new Date(panel.today.getFullYear(), panel.today.getMonth(), 1), "MMMM yyyy")
        color: theme.foreground
        font.pixelSize: 12
        font.family: "monospace"
      }

      GridLayout {
        Layout.fillWidth: true
        columns: 7
        columnSpacing: 0
        rowSpacing: 2

        Repeater {
          model: {
            const y = panel.today.getFullYear();
            const m = panel.today.getMonth();
            const lead = (new Date(y, m, 1).getDay() + 6) % 7; // Monday first
            const days = new Date(y, m + 1, 0).getDate();
            const cells = [];
            for (let i = 0; i < lead; i++)
              cells.push("");
            for (let d = 1; d <= days; d++)
              cells.push(d);
            return cells;
          }

          delegate: Text {
            required property var modelData
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: modelData
            color: modelData === panel.today.getDate() ? theme.accent : theme.foreground
            font.pixelSize: 11
            font.family: "monospace"
          }
        }
      }
    }

    // Power / session
    RowLayout {
      Layout.fillWidth: true
      spacing: 8
      ActionButton {
        theme: panel.theme
        label: "Lock"
        onActivated: {
          panel.run(["hyprlock"]);
          panel.dismiss();
        }
      }
      ActionButton {
        theme: panel.theme
        label: "Log out"
        onActivated: panel.run(["hyprctl", "dispatch", "exit"])
      }
      ActionButton {
        theme: panel.theme
        label: "Suspend"
        onActivated: panel.run(["systemctl", "suspend"])
      }
      ActionButton {
        theme: panel.theme
        label: "Reboot"
        onActivated: panel.run(["systemctl", "reboot"])
      }
      ActionButton {
        theme: panel.theme
        label: "Power off"
        onActivated: panel.run(["systemctl", "poweroff"])
      }
    }
  }
}
