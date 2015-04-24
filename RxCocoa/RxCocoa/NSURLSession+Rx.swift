//
//  NSURLSession+Rx.swift
//  RxCocoa
//
//  Created by Krunoslav Zaher on 3/23/15.
//  Copyright (c) 2015 Krunoslav Zaher. All rights reserved.
//

import Foundation
import UIKit
import RxSwift

func escapeTerminalString(value: String) -> String {
    return value.stringByReplacingOccurrencesOfString("\"", withString: "\\\"", options: NSStringCompareOptions.allZeros, range: nil)
}

func convertURLRequestToCurlCommand(request: NSURLRequest) -> String {
    let method = request.HTTPMethod ?? "GET"
    var returnValue = "curl -i -v -X \(method) "
        
    if  request.HTTPMethod == "POST" && request.HTTPBody != nil {
        let maybeBody = NSString(data: request.HTTPBody!, encoding: NSUTF8StringEncoding) as? String
        if let body = maybeBody {
            returnValue += "-d \"\(maybeBody)\""
        }
    }
    
    for (key, value) in request.allHTTPHeaderFields ?? [:] {
        let escapedKey = escapeTerminalString((key as? String) ?? "")
        let escapedValue = escapeTerminalString((value as? String) ?? "")
        returnValue += "-H \"\(escapedKey): \(escapedValue)\" "
    }
    
    let URLString = request.URL?.absoluteString ?? "<unkown url>"
    
    returnValue += "\"\(escapeTerminalString(URLString))\""
    
    return returnValue
}

func convertResponseToString(data: NSData!, response: NSURLResponse!, error: NSError!, interval: NSTimeInterval) -> String {
    let ms = Int(interval * 1000)
    
    if let response = response as? NSHTTPURLResponse {
        if 200 ..< 300 ~= response.statusCode {
            return "Success (\(ms)ms): Status \(response.statusCode)"
        }
        else {
            return "Failure (\(ms)ms): Status \(response.statusCode)"
        }
    }

    if let error = error {
        if error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled {
            return "Cancelled (\(ms)ms)"
        }
        return "Failure (\(ms)ms): NSError > \(error)"
    }
    
    return "<Unhandled response from server>"
}

extension NSURLSession {
    public func rx_request(request: NSURLRequest) -> Observable<(NSData!, NSURLResponse!)> {
        return create { observer in
            
            // smart compiler should be able to optimize this out
            var d: NSDate!
            
            if Logging.URLRequests {
                d = NSDate()
            }
            
            let task = self.dataTaskWithRequest(request) { (data, response, error) in
                
                if Logging.URLRequests {
                    let interval = NSDate().timeIntervalSinceDate(d)
                    println(convertURLRequestToCurlCommand(request))
                    println(convertResponseToString(data, response, error, interval))
                }
                
                if let error = error {
                    observer.on(.Error(error))
                }
                else {
                    observer.on(.Next(Box(data ?? nil, response ?? nil))) >>> {
                        observer.on(.Completed)
                    } >>! { e in
                        observer.on(.Error(e))
                    }
                }
            }
            
            task.resume()
                
            return success(AnonymousDisposable {
                task.cancel()
            })
        }
    }
    
    public func rx_dataRequest(request: NSURLRequest) -> Observable<NSData> {
        return rx_request(request) >- mapOrDie { (data, response) -> Result<NSData> in
            if let response = response as? NSHTTPURLResponse {
                if 200 ..< 300 ~= response.statusCode {
                    return success(data!)
                }
                else {
                    return .Error(rxError(.NetworkError, "Server return failure", [RxCocoaErrorHTTPResponseKey: response]))
                }
            }
            else {
                rxFatalError("response = nil")
                
                return .Error(UnknownError)
            }
        }
    }
    
    public func rx_JSONWithRequest(request: NSURLRequest) -> Observable<AnyObject!> {
        return rx_dataRequest(request) >- mapOrDie { (data) -> Result<AnyObject!> in
            var serializationError: NSError?
            let result: AnyObject? = NSJSONSerialization.JSONObjectWithData(data, options: NSJSONReadingOptions.allZeros, error: &serializationError)
            
            if let result: AnyObject = result {
                return success(result)
            }
            else {
                return .Error(serializationError!)
            }
        }
    }
    
    public func rx_JSONWithURL(URL: NSURL) -> Observable<AnyObject!> {
        return rx_JSONWithRequest(NSURLRequest(URL: URL))
    }
}