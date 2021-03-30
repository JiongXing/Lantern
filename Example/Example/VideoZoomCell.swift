//
//  VideoZoomCell.swift
//  Example
//
//  Created by 肖志斌 on 2020/9/14.
//  Copyright © 2021 Shenzhen Hive Box Technology Co.,Ltd All rights reserved.
//

import UIKit
import Foundation
import UIKit
import AVFoundation
import Lantern

class VideoZoomCell: UIView, UIScrollViewDelegate, UIGestureRecognizerDelegate, LanternCell, LanternZoomSupportedCell {
    
    /// 弱引用PhotoBrowser
    weak var lantern: Lantern?
    
    var index: Int = 0
    lazy var player = AVPlayer()
    lazy var playerLayer = AVPlayerLayer(player: player)
    
    var imageView: UIImageView = {
        let view = UIImageView()
        view.backgroundColor = .black
        view.clipsToBounds = true
        return view
    }()
    
    var scrollView: UIScrollView = {
        let view = UIScrollView()
        view.maximumZoomScale = 2.0
        view.showsVerticalScrollIndicator = false
        view.showsHorizontalScrollIndicator = false
        if #available(iOS 11.0, *) {
            view.contentInsetAdjustmentBehavior = .never
        }
        return view
    }()
    
    deinit {
        LanternLog.high("deinit - \(self.classForCoder)")
    }
    
    public required override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }
    
    /// 生成实例
    public static func generate(with lantern: Lantern) -> Self {
        let cell = Self.init(frame: .zero)
        cell.lantern = lantern
        return cell
    }
    
    func setup() {
        backgroundColor = .clear
        scrollView.delegate = self
        addSubview(scrollView)
        scrollView.addSubview(imageView)
        imageView.layer.addSublayer(playerLayer)
//        self.layer.insertSublayer(playerLayer, above: imageView.layer)
        /// 拖动手势
        addPanGesture()
        
        // 单击手势
        let singleTap = UITapGestureRecognizer(target: self, action: #selector(onSingleTap(_:)))
        addGestureRecognizer(singleTap)
    }

    
    
    private weak var existedPan: UIPanGestureRecognizer?
    
    /// 添加拖动手势
    func addPanGesture() {
        guard existedPan == nil else {
            return
        }
        let pan = UIPanGestureRecognizer(target: self, action: #selector(onPan(_:)))
        pan.delegate = self
        // 必须加在图片容器上，否则长图下拉不能触发
        scrollView.addGestureRecognizer(pan)
        existedPan = pan
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        scrollView.frame = bounds
        scrollView.setZoomScale(1.0, animated: false)
        let size = computeImageLayoutSize(for: imageView.image, in: scrollView)
        let origin = computeImageLayoutOrigin(for: size, in: scrollView)
        imageView.frame = CGRect(origin: origin, size: size)
        scrollView.setZoomScale(1.0, animated: false)
        playerLayer.frame = CGRect(origin: .zero, size: size)
    }
    
    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        imageView
    }
    
    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        imageView.center = computeImageLayoutCenter(in: scrollView)
    }
    
    func computeImageLayoutSize(for image: UIImage?, in scrollView: UIScrollView) -> CGSize {
        guard let imageSize = image?.size, imageSize.width > 0 && imageSize.height > 0 else {
            return .zero
        }
        var width: CGFloat
        var height: CGFloat
        let containerSize = scrollView.bounds.size
        if containerSize.width < containerSize.height {
            width = containerSize.width
            height = imageSize.height / imageSize.width * width
        } else {
            height = containerSize.height
            width = imageSize.width / imageSize.height * height
            if width > containerSize.width {
                width = containerSize.width
                height = imageSize.height / imageSize.width * width
            }
        }
        
        return CGSize(width: width, height: height)
    }
    
    func computeImageLayoutOrigin(for imageSize: CGSize, in scrollView: UIScrollView) -> CGPoint {
        let containerSize = scrollView.bounds.size
        var y = (containerSize.height - imageSize.height) * 0.5
        y = max(0, y)
        var x = (containerSize.width - imageSize.width) * 0.5
        x = max(0, x)
        return CGPoint(x: x, y: y)
    }
    
    func computeImageLayoutCenter(in scrollView: UIScrollView) -> CGPoint {
        var x = scrollView.contentSize.width * 0.5
        var y = scrollView.contentSize.height * 0.5
        let offsetX = (bounds.width - scrollView.contentSize.width) * 0.5
        if offsetX > 0 {
            x += offsetX
        }
        let offsetY = (bounds.height - scrollView.contentSize.height) * 0.5
        if offsetY > 0 {
            y += offsetY
        }
        return CGPoint(x: x, y: y)
    }
    
    /// 单击
    @objc open func onSingleTap(_ tap: UITapGestureRecognizer) {
        lantern?.dismiss()
    }
    /// 记录pan手势开始时imageView的位置
    private var beganFrame = CGRect.zero
    
    /// 记录pan手势开始时，手势位置
    private var beganTouch = CGPoint.zero
    
    /// 响应拖动
    @objc open func onPan(_ pan: UIPanGestureRecognizer) {
        guard imageView.image != nil else {
            return
        }
        switch pan.state {
        case .began:
            beganFrame = imageView.frame
            beganTouch = pan.location(in: scrollView)
        case .changed:
            let result = panResult(pan)
            imageView.frame = result.frame
            lantern?.maskView.alpha = result.scale * result.scale
            lantern?.setStatusBar(hidden: result.scale > 0.99)
            lantern?.pageIndicator?.isHidden = result.scale < 0.99
        case .ended, .cancelled:
            imageView.frame = panResult(pan).frame
            let isDown = pan.velocity(in: self).y > 0
            if isDown {
                lantern?.dismiss()
            } else {
                lantern?.maskView.alpha = 1.0
                lantern?.setStatusBar(hidden: true)
                lantern?.pageIndicator?.isHidden = false
                resetImageViewPosition()
            }
        default:
            resetImageViewPosition()
        }
    }
    
    /// 计算拖动时图片应调整的frame和scale值
    private func panResult(_ pan: UIPanGestureRecognizer) -> (frame: CGRect, scale: CGFloat) {
        // 拖动偏移量
        let translation = pan.translation(in: scrollView)
        let currentTouch = pan.location(in: scrollView)
        
        // 由下拉的偏移值决定缩放比例，越往下偏移，缩得越小。scale值区间[0.3, 1.0]
        let scale = min(1.0, max(0.3, 1 - translation.y / bounds.height))
        
        let width = beganFrame.size.width * scale
        let height = beganFrame.size.height * scale
        
        // 计算x和y。保持手指在图片上的相对位置不变。
        // 即如果手势开始时，手指在图片X轴三分之一处，那么在移动图片时，保持手指始终位于图片X轴的三分之一处
        let xRate = (beganTouch.x - beganFrame.origin.x) / beganFrame.size.width
        let currentTouchDeltaX = xRate * width
        let x = currentTouch.x - currentTouchDeltaX
        
        let yRate = (beganTouch.y - beganFrame.origin.y) / beganFrame.size.height
        let currentTouchDeltaY = yRate * height
        let y = currentTouch.y - currentTouchDeltaY
        
        return (CGRect(x: x.isNaN ? 0 : x, y: y.isNaN ? 0 : y, width: width, height: height), scale)
    }
    
    /// 复位ImageView
    private func resetImageViewPosition() {
        // 如果图片当前显示的size小于原size，则重置为原size
        let size = computeImageLayoutSize(for: imageView.image, in: scrollView)
        let needResetSize = imageView.bounds.size.width < size.width || imageView.bounds.size.height < size.height
        UIView.animate(withDuration: 0.25) {
            self.imageView.center = self.computeImageLayoutCenter(in: self.scrollView)
            if needResetSize {
                self.imageView.bounds.size = size
            }
        }
    }
    
    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        // 只处理pan手势
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer else {
            return true
        }
        let velocity = pan.velocity(in: self)
        // 向上滑动时，不响应手势
        if velocity.y < 0 {
            return false
        }
        // 横向滑动时，不响应pan手势
        if abs(Int(velocity.x)) > Int(velocity.y) {
            return false
        }
        // 向下滑动，如果图片顶部超出可视区域，不响应手势
        if scrollView.contentOffset.y > 0 {
            return false
        }
        // 响应允许范围内的下滑手势
        return true
    }
    
    var showContentView: UIView {
        return imageView
    }
}
