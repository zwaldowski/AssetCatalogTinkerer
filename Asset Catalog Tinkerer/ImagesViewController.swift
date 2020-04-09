//
//  ViewController.swift
//  Asset Catalog Tinkerer
//
//  Created by Guilherme Rambo on 27/03/16.
//  Copyright © 2016 Guilherme Rambo. All rights reserved.
//

import Cocoa

class ImagesViewController: NSViewController, NSMenuItemValidation {

    var progress: Progress? {
        didSet {
            progressBar.observedProgress = progress
        }
    }
    
    var error: Error? {
        didSet {
            guard let error = error else { return }
            progress = nil
            dataProvider.images = []
            showStatus(error.localizedDescription)
            tellWindowControllerToDisableSearchField()
        }
    }
    
    private var dataProvider = ImagesCollectionViewDataProvider()
    
    var images = [[AssetCatalogImageKey: Any]]() {
        didSet {
            progress = nil
            dataProvider.images = images
            hideStatus()
            tellWindowControllerToEnableSearchField()
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        buildUI()
        showStatus("Extracting Images...")
    }
    
    // MARK: - UI
    
    private lazy var progressBar = ProgressBar()

    fileprivate lazy var statusLabel: NSTextField = {
        let l = NSTextField()
        
        l.translatesAutoresizingMaskIntoConstraints = false
        l.isBordered = false
        l.isBezeled = false
        l.isEditable = false
        l.isSelectable = false
        l.drawsBackground = false
        l.font = NSFont.systemFont(ofSize: 12.0, weight: .medium)
        l.textColor = .secondaryLabelColor
        l.lineBreakMode = .byTruncatingTail

        l.alphaValue = 0.0
        
        return l
    }()
    
    private lazy var scrollView = NSScrollView()
    private lazy var collectionView = QuickLookableCollectionView()
    
    private lazy var exportProgressView: NSVisualEffectView = {
        let vfxView = NSVisualEffectView(frame: NSZeroRect)
        
        vfxView.translatesAutoresizingMaskIntoConstraints = false
        vfxView.material = .mediumLight
        vfxView.blendingMode = .withinWindow
        
        let p = NSProgressIndicator(frame: NSZeroRect)
        
        p.translatesAutoresizingMaskIntoConstraints = false
        p.style = .spinning
        p.controlSize = .regular
        p.sizeToFit()
        
        vfxView.addSubview(p)
        p.centerYAnchor.constraint(equalTo: vfxView.centerYAnchor).isActive = true
        p.centerXAnchor.constraint(equalTo: vfxView.centerXAnchor).isActive = true
        
        vfxView.alphaValue = 0.0
        vfxView.isHidden = true
        p.startAnimation(nil)
        
        return vfxView
    }()
    
    private func buildUI() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        view.addSubview(scrollView)

        collectionView.isSelectable = true
        collectionView.allowsMultipleSelection = true
        dataProvider.collectionView = collectionView
        scrollView.documentView = collectionView

        progressBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(progressBar)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            progressBar.topAnchor.constraint(equalTo: view.topAnchor),
            progressBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            progressBar.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
    }
    
    fileprivate func showExportProgress() {
        tellWindowControllerToDisableSearchField()
        
        if exportProgressView.superview == nil {
            exportProgressView.frame = view.bounds
            view.addSubview(exportProgressView)
            exportProgressView.topAnchor.constraint(equalTo: view.topAnchor).isActive = true
            exportProgressView.bottomAnchor.constraint(equalTo: view.bottomAnchor).isActive = true
            exportProgressView.leadingAnchor.constraint(equalTo: view.leadingAnchor).isActive = true
            exportProgressView.trailingAnchor.constraint(equalTo: view.trailingAnchor).isActive = true
        }
        
        exportProgressView.isHidden = false
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.4
            self.exportProgressView.animator().alphaValue = 1.0
        })
    }
    
    fileprivate func hideExportProgress() {
        tellWindowControllerToEnableSearchField()
        
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.4
            self.exportProgressView.animator().alphaValue = 0.0
        }, completionHandler: {
            self.exportProgressView.isHidden = true
        })
    }
    
    fileprivate func showStatus(_ status: String) {
        if statusLabel.superview == nil {
            view.addSubview(statusLabel)
            statusLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor).isActive = true
            statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor).isActive = true
        }
        
        statusLabel.stringValue = status
        statusLabel.isHidden = false
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.4
            self.statusLabel.animator().alphaValue = 1.0
        })
    }
    
    fileprivate func hideStatus() {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.4
            self.statusLabel.animator().alphaValue = 0.0
        }, completionHandler: {
            self.statusLabel.isHidden = true
        })
    }
    
    @IBAction func search(_ sender: NSSearchField) {
        dataProvider.searchTerm = sender.stringValue
        
        if dataProvider.filteredImages.count == 0 {
            showStatus("No images found for \"\(dataProvider.searchTerm)\"")
        } else {
            hideStatus()
        }
    }
    
    fileprivate func tellWindowControllerToEnableSearchField() {
        NSApp.sendAction(#selector(MainWindowController.enableSearchField), to: nil, from: self)
    }
    
    fileprivate func tellWindowControllerToDisableSearchField() {
        NSApp.sendAction(#selector(MainWindowController.disableSearchField), to: nil, from: self)
    }
    
    // MARK: - Export
    
    func copy(_ sender: Any?) {
        guard !collectionView.selectionIndexPaths.isEmpty else { return }
        _ = dataProvider.collectionView(collectionView, writeItemsAt: collectionView.selectionIndexPaths, to: .general)
    }
    
    @IBAction func exportAllImages(_ sender: NSMenuItem) {
        imagesToExport = dataProvider.filteredImages
        launchExportPanel()
    }
    
    @IBAction func exportSelectedImages(_ sender: NSMenuItem) {
        imagesToExport = collectionView.selectionIndexes.map { return self.dataProvider.filteredImages[$0] }
        launchExportPanel()
    }
    
    fileprivate var imagesToExport: [[AssetCatalogImageKey: Any]]?
    
    fileprivate func launchExportPanel() {
        guard let imagesToExport = imagesToExport,
            let window = view.window else { return }
        
        let panel = NSOpenPanel()
        panel.prompt = "Export"
        panel.title = "Select a directory to export the images to"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        
        panel.beginSheetModal(for: window) { result in
            guard result == .OK,
                let url = panel.url else { return }
            
            self.exportImages(imagesToExport, toDirectoryAt: url)
        }
    }
    
    fileprivate func exportImages(_ images: [[AssetCatalogImageKey: Any]], toDirectoryAt url: URL) {
        showExportProgress()
        
        DispatchQueue.global(qos: .userInitiated).async {
            images.forEach { image in
                guard let filename = image[.filename] as? String,
                    let pngData = image[.pngData] as? Data else { return }

                let url = url.appendingPathComponent(filename)
                
                do {
                    try pngData.write(to: url, options: .atomic)
                } catch {
                    NSLog("ERROR: Unable to write \(filename) to \(url)")
                }
            }
            
            DispatchQueue.main.async {
                self.hideExportProgress()
            }
        }
    }
    
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(NSText.copy(_:)), #selector(exportSelectedImages):
            return !collectionView.selectionIndexPaths.isEmpty
        case #selector(exportAllImages):
            return !images.isEmpty
        default:
            return false
        }
    }

}

