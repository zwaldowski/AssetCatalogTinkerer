//
//  ProgressBar.swift
//  Asset Catalog Tinkerer
//
//  Created by Guilherme Rambo on 27/03/16.
//  Copyright © 2016 Guilherme Rambo. All rights reserved.
//

import Cocoa

class ProgressBar: NSView {

    private static var observationContext = false
    private let progressLayer = CALayer()
    private var animateOnNextUpdateLayer = false

    // MARK: -
    
    var tintColor: NSColor? {
        didSet {
            needsDisplay = true
        }
    }
    
    var progress: Double = 0.0 {
        didSet {
            animateOnNextUpdateLayer = oldValue < progress
            needsDisplay = true
        }
    }

    var observedProgress: Progress? {
        didSet {
            guard observedProgress != oldValue else { return }
            oldValue?.removeObserver(self, forKeyPath: #keyPath(Progress.fractionCompleted), context: &Self.observationContext)
            observedProgress?.addObserver(self, forKeyPath: #keyPath(Progress.fractionCompleted), context: &Self.observationContext)
            if let observedProgress = observedProgress {
                update(for: observedProgress)
            }
        }
    }

    // MARK: - NSView

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        if progressLayer.superlayer == nil {
            progressLayer.frame = bounds
            progressLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
            layer!.addSublayer(progressLayer)
        }
        updateProgressLayer(animated: animateOnNextUpdateLayer)
        animateOnNextUpdateLayer = false
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: 3)
    }

    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        guard context == &Self.observationContext, let observedProgress = object as? Progress else {
            return super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
        }
        update(for: observedProgress)
    }

    // MARK: -
    
    private var widthForProgressLayer: CGFloat {
        return bounds.width * CGFloat(progress)
    }
    
    private func updateProgressLayer(animated: Bool) {
        CATransaction.begin()
        CATransaction.setAnimationDuration(animateOnNextUpdateLayer ? 0.4 : 0.0)
        defer { CATransaction.commit() }

        progressLayer.backgroundColor = (tintColor ?? .controlAccentColor).cgColor
        progressLayer.frame.size.width = widthForProgressLayer
        
        if progress >= 0.99 {
            progressLayer.opacity = 0.0
        } else {
            progressLayer.opacity = 1.0
        }
    }

    private func update(for observedProgress: Progress) {
        if Thread.isMainThread, observedProgress == self.observedProgress {
            progress = observedProgress.fractionCompleted
        } else {
            DispatchQueue.main.async {
                self.update(for: observedProgress)
            }
        }
    }
    
}
