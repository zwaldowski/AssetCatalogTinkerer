//
//  ImagesCollectionViewDataProvider.swift
//  Asset Catalog Tinkerer
//
//  Created by Guilherme Rambo on 27/03/16.
//  Copyright © 2016 Guilherme Rambo. All rights reserved.
//

import Cocoa

extension NSUserInterfaceItemIdentifier {
    static let imageItemIdentifier = NSUserInterfaceItemIdentifier("ImageItemIdentifier")
}

class ImagesCollectionViewDataProvider: NSObject, NSCollectionViewDataSource, NSCollectionViewDelegate {
    
    fileprivate struct Constants {
        static let nibName = "ImageCollectionViewItem"

    }
    
    var collectionView: NSCollectionView! {
        didSet {
            collectionView.setDraggingSourceOperationMask(.copy, forLocal: false)
            
            collectionView.delegate = self
            collectionView.dataSource = self
            
            collectionView.collectionViewLayout = GridLayout()
            
            let nib = NSNib(nibNamed: Constants.nibName, bundle: nil)
            collectionView.register(nib, forItemWithIdentifier: .imageItemIdentifier)
        }
    }
    
    var images = [[AssetCatalogImageKey: Any]]() {
        didSet {
            filteredImages = filterImagesWithCurrentSearchTerm()
            collectionView.reloadData()
        }
    }
    
    var searchTerm = "" {
        didSet {
            filteredImages = filterImagesWithCurrentSearchTerm()
            collectionView.reloadData()
        }
    }
    
    var filteredImages = [[AssetCatalogImageKey: Any]]()
    
    fileprivate func filterImagesWithCurrentSearchTerm() -> [[AssetCatalogImageKey: Any]] {
        guard !searchTerm.isEmpty else { return images }
        
        let predicate = NSPredicate(format: "name contains[cd] %@", searchTerm)
        return (images as NSArray).filtered(using: predicate) as! [[AssetCatalogImageKey: Any]]
    }
    
    func numberOfSections(in collectionView: NSCollectionView) -> Int {
        return 1
    }
    
    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let item = collectionView.makeItem(withIdentifier: .imageItemIdentifier, for: indexPath) as! ImageCollectionViewItem
        
        item.image = filteredImages[indexPath.item]
        
        return item
    }
    
    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        return filteredImages.count
    }
    
    func collectionView(_ collectionView: NSCollectionView, writeItemsAt indexPaths: Set<IndexPath>, to pasteboard: NSPasteboard) -> Bool {
        let images = indexPaths.compactMap { (indexPath) -> URL? in
            let index = indexPath.item

            guard let filename = self.filteredImages[index][.filename] as? String,
                let data = self.filteredImages[index][.pngData] as? Data else { return nil }

            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
            do {
                try data.write(to: tempURL)
            } catch {
                return nil
            }
            return tempURL
        }

        pasteboard.clearContents()
        pasteboard.writeObjects(images as [NSURL])
        
        return true
    }
    
}
