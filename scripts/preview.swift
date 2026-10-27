// Triggers Cadence's 10-second lock screen preview: swift scripts/preview.swift
import Foundation

DistributedNotificationCenter.default().postNotificationName(.init("local.cadence.preview"), object: nil,
                                                             userInfo: nil, deliverImmediately: true)
