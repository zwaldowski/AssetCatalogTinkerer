//
//  Document.swift
//  Asset Catalog Tinkerer
//
//  Created by Guilherme Rambo on 27/03/16.
//  Copyright © 2016 Guilherme Rambo. All rights reserved.
//

import Cocoa
import ACS

class AssetCatalogDocument: NSDocument {

    fileprivate var reader: AssetCatalogReader!

    var progress: Progress?

    deinit {
        progress?.cancel()
    }

    override func makeWindowControllers() {
        let storyboard = NSStoryboard(name: "Main", bundle: nil)
        let windowController = storyboard.instantiateController(withIdentifier: "Document Window Controller") as! NSWindowController
        self.addWindowController(windowController)
        
        windowController.window?.tabbingIdentifier = "ACTWindow"
        windowController.window?.tabbingMode = .preferred

        NotificationCenter.default.addObserver(self, selector: #selector(onWindowWillClose), name: NSWindow.willCloseNotification, object: windowController.window)

        imagesViewController?.progress = progress
    }
    
    fileprivate var imagesViewController: ImagesViewController? {
        return windowControllers.first?.contentViewController as? ImagesViewController
    }

    override func read(from url: URL, ofType typeName: String) throws {
        reader = AssetCatalogReader(fileURL: url)
        reader.thumbnailSize = NSSize(width: 138.0, height: 138.0)
        
        reader.distinguishCatalogsFromThemeStores = Preferences.shared[.distinguishCatalogsAndThemeStores]
        reader.ignorePackedAssets = Preferences.shared[.ignorePackedAssets]

        progress = reader.read { [weak self] (images, _, error) in
            guard let self = self else { return }
            if let error = error {
                self.imagesViewController?.error = error
            } else {
                self.imagesViewController?.images = images ?? []
            }
        }
    }

    @objc private func onWindowWillClose(_ note: Notification) {
        progress?.cancel()
    }

}
