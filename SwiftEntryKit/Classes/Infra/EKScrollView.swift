//
//  EKScrollView.swift
//  SwiftEntryKit
//
//  Created by Daniel Huri on 4/19/18.
//  Copyright (c) 2018 huri000@gmail.com. All rights reserved.
//

import UIKit

protocol EntryScrollViewDelegate: class {
    func changeToActive(withAttributes attributes: EKAttributes)
    func changeToInactive(withAttributes attributes: EKAttributes)
}

class EKScrollView: UIScrollView {
    
    // MARK: Props
    private weak var entryDelegate: EntryScrollViewDelegate!
    
    private var outDispatchWorkItem: DispatchWorkItem!
    
    private var outConstraint: NSLayoutConstraint!
    private var inConstraint: NSLayoutConstraint!
    
    private var attributes: EKAttributes!
    private var contentView: UIView!
    
    // MARK: Setup
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    init(withEntryDelegate entryDelegate: EntryScrollViewDelegate) {
        self.entryDelegate = entryDelegate
        super.init(frame: .zero)
        setupAttributes()
    }
    
    func setup(with contentView: UIView, attributes: EKAttributes) {
        self.attributes = attributes
        self.contentView = contentView
        
        // Enable / disable scroll
        isScrollEnabled = attributes.options.scroll.isLooselyEnabled
        
        // Determine the layout entrance type according to the entry type
        let messageBottomInSuperview: NSLayoutAttribute
        let messageTopInSuperview: NSLayoutAttribute
        var inOffset: CGFloat = 0
        var outOffset: CGFloat = 0

        var totalEntryHeight: CGFloat = 0
        
        // Define a spacer to catch top / bottom offsets
        var spacerView: UIView!
        let safeAreaInsets = EKWindowProvider.safeAreaInsets
        let ignoreSafeArea = attributes.options.ignoreSafeArea

        if !ignoreSafeArea && safeAreaInsets.hasVerticalInsets {
            spacerView = UIView()
            addSubview(spacerView)
            spacerView.set(.height, of: safeAreaInsets.top)
            spacerView.layoutToSuperview(.width, .centerX)
            
            totalEntryHeight += safeAreaInsets.top
        }
        
        switch attributes.location {
        case .top:
            messageBottomInSuperview = .top
            messageTopInSuperview = .bottom
            
            if ignoreSafeArea {
                inOffset = -safeAreaInsets.top
            } else {
                inOffset = safeAreaInsets.top
            }
            switch attributes.shape {
            case .floating(info: let info):
                inOffset += info.verticalOffset
            default:
                break
            }
            outOffset = -safeAreaInsets.top
            
            spacerView?.layout(.bottom, to: .top, of: self)

        case .bottom:
            messageBottomInSuperview = .bottom
            messageTopInSuperview = .top
            
            inOffset = -safeAreaInsets.bottom
            switch attributes.shape {
            case .floating(info: let info):
                inOffset -= info.verticalOffset
            default:
                break
            }
            
            spacerView?.layout(.top, to: .bottom, of: self)
        }
        
        // Layout the content view inside the scroll view
        addSubview(contentView)
        contentView.layoutToSuperview(.left, .right, .top, .bottom)
        contentView.layoutToSuperview(.width, .height)
        
        // Layout the scroll view itself according to the entry type
        outConstraint = layout(messageTopInSuperview, to: messageBottomInSuperview, of: superview!, offset: outOffset, priority: .must)
        inConstraint = layout(to: messageBottomInSuperview, of: superview!, offset: inOffset, priority: .defaultLow)
        
        // Layout the scroll view horizontally
        let horizontalInsets: CGFloat
        switch attributes.shape {
        case .stretched:
            horizontalInsets = 0
        case .floating(info: let info):
            horizontalInsets = info.horizontalOffset
        }
        layoutToSuperview(axis: .horizontally, offset: horizontalInsets)
        
        animateIn()
        
        setupTapGestureRecognizer()
    }

    private func setupAttributes() {
        clipsToBounds = false
        alwaysBounceVertical = true
        bounces = true
        showsVerticalScrollIndicator = false
        isPagingEnabled = true
        delegate = self
    }
    
    private func setupTapGestureRecognizer() {
        guard attributes.contentInteraction.isResponsive else {
            return
        }
        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(tapGestureRecognized))
        tapGestureRecognizer.numberOfTapsRequired = 1
        addGestureRecognizer(tapGestureRecognizer)
    }
    
    // MARK: State Change / Animations
    private func changeToActiveState() {
        inConstraint.priority = .must
        outConstraint.priority = .defaultLow
        superview?.layoutIfNeeded()
    }
    
    private func changeToInactiveState() {
        inConstraint.priority = .defaultLow
        outConstraint.priority = .must
        superview?.layoutIfNeeded()
    }
    
    func removeFromSuperview(keepWindow: Bool) {
        super.removeFromSuperview()
        if EKAttributes.count > 0 {
            EKAttributes.count -= 1
        }
        if !keepWindow && !EKAttributes.isPresenting {
            EKWindowProvider.shared.state = .main
        }
    }
    
    func animateOut(rollOut: Bool) {
        
        outDispatchWorkItem?.cancel()
        entryDelegate?.changeToInactive(withAttributes: attributes)
        
        if let rollOutAnimation = attributes.rollOutAdditionalAnimation, rollOut {
            UIView.animate(withDuration: rollOutAnimation.duration, delay: 0, options: [.curveEaseOut], animations: {
                if rollOutAnimation.types.contains(.scale) {
                    self.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
                }
                if rollOutAnimation.types.contains(.fade) {
                    self.alpha = 0
                }
            }, completion: nil)
        }
        
        UIView.animate(withDuration: attributes.exitAnimation.duration, delay: 0.1, options: [.beginFromCurrentState], animations: {
            self.changeToInactiveState()
        }, completion: { finished in
            self.removeFromSuperview(keepWindow: false)
        })
    }
    
    private func scheduleAnimateOut() {
        outDispatchWorkItem?.cancel()
        outDispatchWorkItem = DispatchWorkItem { [weak self] in
            self?.animateOut(rollOut: false)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + attributes.entranceAnimation.duration + attributes.visibleDuration, execute: outDispatchWorkItem)
    }
    
    private func animateIn() {
        
        // Increment entry count
        EKAttributes.count += 1
    
        // Change to active state
        superview?.layoutIfNeeded()
        UIView.animate(withDuration: attributes.entranceAnimation.duration, delay: 0, options: [.curveEaseOut, .beginFromCurrentState], animations: {
            self.changeToActiveState()
        }, completion: nil)
    
        entryDelegate?.changeToActive(withAttributes: attributes)

        scheduleAnimateOut()
    }
    
    // Removes the view promptly - DOES NOT animate out
    func removePromptly(keepWindow: Bool = true) {
        outDispatchWorkItem?.cancel()
        entryDelegate?.changeToInactive(withAttributes: attributes)
        removeFromSuperview(keepWindow: keepWindow)
    }
    
    // MARK: Tap Gesture Handler
    @objc func tapGestureRecognized() {
        switch attributes.contentInteraction.defaultAction {
        case .dismissEntry:
            animateOut(rollOut: true)
            fallthrough
        default:
            attributes.contentInteraction.customActions.forEach { $0() }
        }
    }
}

// MARK: UIScrollViewDelegate
extension EKScrollView: UIScrollViewDelegate {
    
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard let scrollAttribute = attributes?.options.scroll, scrollAttribute.isEdgeCrossingDisabled else {
            return
        }
        if attributes.location.isTop && contentOffset.y < 0 {
            contentOffset.y = 0
        } else if !attributes.location.isTop && scrollView.bounds.maxY > scrollView.contentSize.height {
            contentOffset.y = 0
        }
    }
}

// MARK: UIResponder
extension EKScrollView {
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if attributes.contentInteraction.isDelayExit {
            outDispatchWorkItem?.cancel()
        }
        //        UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 1, initialSpringVelocity: 0, options: [.beginFromCurrentState, .allowUserInteraction], animations: {
        //            self.contentView?.transform = CGAffineTransform(scaleX: 1.05, y: 1.05)
        //        }, completion: nil)
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        if attributes.contentInteraction.isDelayExit {
            scheduleAnimateOut()
        }
        //        UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 1, initialSpringVelocity: 0, options: [.beginFromCurrentState, .allowUserInteraction], animations: {
        //            self.contentView?.transform = .identity
        //        }, completion: nil)
    }
    
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchesEnded(touches, with: event)
    }
}