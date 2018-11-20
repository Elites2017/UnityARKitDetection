//
//  VisionClassification.swift
//  Vision
//
//  Created by Adam Hegedus on 2018. 06. 15..
//

import Foundation

@objc public class VisionClassification : NSObject
{
    @objc public var confidence : Float = 0
    @objc public var xMin : Float = 0
    @objc public var xMax : Float = 0
    @objc public var yMin : Float = 0
    @objc public var yMax : Float = 0
    @objc public var identifier : String = ""

    public init(identifier: String, confidence: Float, xMin: Float, yMin: Float, xMax: Float, yMax: Float)
    {
        self.confidence = confidence
        self.xMin = xMin
        self.yMin = yMin
        self.xMax = xMax
        self.yMax = yMax
        self.identifier = identifier
    }
}
