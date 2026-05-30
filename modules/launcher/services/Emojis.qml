pragma Singleton

import QtQuick
import Quickshell
import Caelestia.Config
import Caelestia.Models

Item {
    id: root
    
    property alias model: internalModel
    property string currentSearch: ""

    function transformSearch(search: string): string {
        return search.slice(1).trim(); // Remove the ';' prefix
    }

    EmojiModel {
        id: internalModel
        query: root.currentSearch
    }
}
