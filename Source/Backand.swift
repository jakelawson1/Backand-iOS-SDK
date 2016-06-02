//
//  Backand.swift
//  Backand-iOS-SDK
//
//  Created by Jake Lawson on 28/05/2016.
//  Copyright © 2016 Jake Lawson. All rights reserved.
//

import Foundation
import Alamofire
import SwiftKeychainWrapper

/// HTTP method definitions.
public enum Method: String {
    case POST, GET, PUT, DELETE
}

/// Request options
public enum BackandOption {
    case PageSize(Int)
    case PageNumber(Int)
    case FilterArray([Filter])
    case ExcludeArray([ExcludeOption])
    case Deep(Bool)
    case RelatedObjects(Bool)
    case ReturnObject(Bool)
    case Search(String)
}

public enum ExcludeOption: String {
    case Metadata = "__metadata"
    case TotalRows = "totalRows"
}

/** 
    Filter's allow you to apply constraints to the data that is returned.
    - parameters:
        - filedName: The name of the field you want to apply the filter to.
        - operatorType: The operation to be applied the field. E.g. Equal.
        - value: The value to compare with.
*/
public struct Filter {
    enum OperatorType: String {
        case Equal = "equals"
        case NotEqual = "notEquals"
        case StartsWith = "startsWith"
        case EndsWith = "endsWith"
        case Contains = "contains"
        case NotContains = "notContains"
        case Empty = "empty"
        case NotEmpty = "notEmpty"
    }
    
    let fieldName: String
    let operatorType: OperatorType
    let value: AnyObject
    
    func asObject() -> [String: AnyObject] {
        var object: [String: AnyObject] = [:]
        object["fieldName"] = fieldName
        object["operator"] = operatorType.rawValue
        object["value"] = value
        return object
    }
}

/**
     Action's can be used to create bulk operations.
     - parameters:
         - method: HTTP method. Possible values: POST, PUT & DELETE.
         - url: The URL for the object.
         - data: JSON hash.
*/
public struct Action {
    let method: Method
    let url: String
    let data: [String: AnyObject]?
    
    func asObject() -> [String: AnyObject] {
        var object: [String: AnyObject] = [:]
        object["method"] = method.rawValue
        object["url"] = url
        if let data = data {
            object["data"] = data
        }
        return object
    }
}

/// Basic class to interact with Backand REST API.
public class Backand: NSObject {
    
    // MARK: Types
    
    public typealias CompletionHandlerType = (Result) -> Void
    
    /// Used to represent whether a request was successful or not.
    public enum Result {
        case Success(AnyObject?)
        case Failure(NSError)
    }
    
    public enum BackandAuth {
        case Anonymous, User, SignUp
    }
    
    private struct Constants {
        static let userTokenKey = "userTokenKey"
    }

    /// Manages all requests sent to Backand
    private enum Router: URLRequestConvertible {
        static var baseURLString = "https://api.backand.com"
        static var apiVersion = "1"
        static var appName: String?
        static var authMode: BackandAuth = .Anonymous
        static var signUpToken: String?
        static var anonymousToken: String?
        static var userToken: String? {
            get {
                return KeychainWrapper.stringForKey(Constants.userTokenKey)
            }
            set {
                if let token = newValue {
                    KeychainWrapper.setString(token, forKey: Constants.userTokenKey)
                } else {
                    KeychainWrapper.removeObjectForKey(Constants.userTokenKey)
                }
            }
        }
        
        case CreateItem(name: String, query: String?, parameters: [String: AnyObject])
        case UpdateItem(name: String, id: String, query: String?, parameters: [String: AnyObject])
        case ReadItem(name: String, id: String, query: String?)
        case ReadItems(name: String, query: String?)
        case DeleteItem(name: String, id: String)
        case RunQuery(name: String, parameters: [String: AnyObject]?)
        case PerformActions(body: [[String: AnyObject]])
        case SignUp(user: [String: AnyObject])
        case SignIn(username: String, password: String)
        
        var method: Alamofire.Method {
            switch self {
            case .CreateItem, .PerformActions, .SignUp, .SignIn:
                return .POST
            case .ReadItem, .ReadItems, .RunQuery:
                return .GET
            case .UpdateItem:
                return .PUT
            case .DeleteItem:
                return .DELETE
            }
        }
        
        var path: String {
            switch self {
            case .CreateItem(let name, let query, _):
                return "/\(Router.apiVersion)/objects/\(name)"+(query ?? "")
            case .ReadItem(let name, let id, let query):
                return "/\(Router.apiVersion)/objects/\(name)/\(id)"+(query ?? "")
            case .ReadItems(let name, let query):
                return "/\(Router.apiVersion)/objects/\(name)"+(query ?? "")
            case .UpdateItem(let name, let id, let query, _):
                return "/\(Router.apiVersion)/objects/\(name)/\(id)"+(query ?? "")
            case .DeleteItem(let name, let id):
                return "/\(Router.apiVersion)/objects/\(name)/\(id)"
            case .RunQuery(let name, _):
                return "/\(Router.apiVersion)/query/data/\(name)"
            case .PerformActions:
                return "/\(Router.apiVersion)/bulk"
            case .SignUp:
                return "/\(Router.apiVersion)/user/signup"
            case .SignIn:
                return "/token"
            }
        }
        
        // MARK: URLRequestConvertible
        
        var URLRequest: NSMutableURLRequest {
            let URL = NSURL(string: Router.baseURLString+path)!
            let mutableURLRequest = NSMutableURLRequest(URL: URL)
            mutableURLRequest.HTTPMethod = method.rawValue
            
            switch Router.authMode {
            case .Anonymous:
                mutableURLRequest.setValue(Router.anonymousToken, forHTTPHeaderField: "AnonymousToken")
            case .User:
                mutableURLRequest.setValue("Bearer \(Router.userToken ?? "")", forHTTPHeaderField: "Authorization")
            case .SignUp:
                mutableURLRequest.setValue(Router.signUpToken, forHTTPHeaderField: "SignUpToken")
            }
            mutableURLRequest.setValue(Router.appName, forHTTPHeaderField: "AppName")
            
            switch self {
            case .CreateItem(_, _, let parameters):
                return Alamofire.ParameterEncoding.JSON.encode(mutableURLRequest, parameters: parameters).0
            case .UpdateItem(_, _, _, let parameters):
                return Alamofire.ParameterEncoding.JSON.encode(mutableURLRequest, parameters: parameters).0
            case .RunQuery(_, let parameters):
                return Alamofire.ParameterEncoding.URL.encode(mutableURLRequest, parameters: parameters).0
            case .PerformActions(let body):
                mutableURLRequest.HTTPBody = try! NSJSONSerialization.dataWithJSONObject(body, options: NSJSONWritingOptions())
                return mutableURLRequest
            case .SignUp(let user):
                return Alamofire.ParameterEncoding.JSON.encode(mutableURLRequest, parameters: user).0
            case .SignIn(let username, let password):
                let params = ["username": username, "password": password, "grant_type": "password", "appName": Router.appName ?? ""]
                return Alamofire.ParameterEncoding.URL.encode(mutableURLRequest, parameters: params).0
            default:
                return mutableURLRequest
            }
        }
    }
    
    // MARK: Properties
    
    public static let sharedInstance = Backand()
    
    // MARK: Configuration methods
    
    /**
         Sets the Backand app name for your application.
         - parameter name:  The app name string.
    */
    public func setAppName(name: String) {
        Router.appName = name
    }
    
    /**
        Sets the value of the anonymous use token.
        - parameter token:  The application's anonymous token string.
    */
    public func setAnonymousToken(token: String) {
        Router.anonymousToken = token
    }
    
    /**
         Sets the value of the user registration token.
         - parameter token:   The application's sign up token string.
    */
    public func setSignUpToken(token: String) {
        Router.signUpToken = token
    }
    
    /**
         Sets the base API URL for this application. Defualt value is "https://api.backand.com".
         - parameter url:  The API URL string.
    */
    public func setApiUrl(url: String) {
        Router.baseURLString = url
    }
    
    /**
         Returns the base API URL for this application.
         - returns: A string representing the base API URL.
    */
    public func getApiUrl() -> String {
        return Router.baseURLString
    }
    
    /**
        Change authenication mode.
        - parameter mode: Authentication mode.
    */
    public func setAuthMode(mode: BackandAuth) {
        Router.authMode = mode
    }
    
    // MARK: Authentication
    
    /**
         Registers a user for the application.
         - parameters:
             - user: User dictionary.
             - signinAfterSignup: Performs a sign in after a user signs up. This configuration is irrelevant when signing up with a social provider, since the user is always signed in after sign-up.
             - handler: The code to be executed once the request has finished.
    */
    public func signUp(user: [String: AnyObject], signinAfterSignup: Bool = true, handler: CompletionHandlerType) {
        Router.authMode = .SignUp
        Alamofire.request(Router.SignUp(user: user)).validate().responseJSON { response in
            switch response.result {
            case .Success:
                if signinAfterSignup {
                    if let JSON = response.result.value {
                        if let token = JSON["token"] as? String {
                            Router.userToken = token
                            Router.authMode = .User
                        }
                    }
                }
                handler(Result.Success(response.result.value))
            case .Failure(let error):
                handler(Result.Failure(error))
            }
        }
    }
    
    /**
        Signs the specified user into the application.
        - parameters:
            - username: The user's email.
            - password: The user's password.
            - handler: The code to be executed once the request has finished.
    */
    public func signIn(username: String, password: String, handler: CompletionHandlerType) {
        Alamofire.request(Router.SignIn(username: username, password: password)).validate().responseJSON { response in
            switch response.result {
            case .Success:
                if let JSON = response.result.value {
                    if let token = JSON["access_token"] as? String {
                        Router.userToken = token
                        Router.authMode = .User
                    }
                }
                handler(Result.Success(response.result.value))
            case .Failure(let error):
                handler(Result.Failure(error))
            }
        }
    }
    
    /// Signs the currently authenticated user out of the application.
    public func signOut() {
        Router.userToken = nil
        Router.authMode = .Anonymous
    }
    
    /**
        Returns status of user sign in.
        - returns: True if user is signed in and false if not.
    */
    public func userSignedIn() -> Bool {
        return (Router.userToken != nil) ? true : false
    }
    
    // MARK: Query string
    
    /**
        Converts an array of BackandOption into a query string
        - parameter options: An array of BackandOption(s).
        - returns: A query string.
    */
    private func queryStringFromOptions(options: [BackandOption]) -> String {
        /**
            Converts an Array of Filter objects into a query string.
            - parameter filters: An array of Filter(s).
            - returns: A query string.
        */
        func filterStringFromFilters(filters: [Filter]) -> String? {
            var filterArray = [[String: AnyObject]]()
            for filter in filters {
                filterArray.append(filter.asObject())
            }
            var filterString: String?
            let jsonData = try! NSJSONSerialization.dataWithJSONObject(filterArray, options: [])
            if let jsonString = NSString(data: jsonData, encoding: NSASCIIStringEncoding) {
                if let encodedString = jsonString.stringByAddingPercentEncodingWithAllowedCharacters(NSCharacterSet.URLQueryAllowedCharacterSet()) {
                    filterString = encodedString
                }
            }
            return filterString
        }
        
        /**
            Converts an Array of ExcludeOption objects into a query string.
            - parameter options: An array of Filter(s).
            - returns: A query string.
        */
        func excludeStringFromExcludeOptions(options: [ExcludeOption]) -> String {
            var excludeString = ""
            for (index, exclude) in options.enumerate() {
                excludeString += exclude.rawValue
                if index != options.count-1 {
                    excludeString += ","
                }
            }
            return excludeString
        }
        
        var query = "?"
        for (index, option) in options.enumerate() {
            switch option {
            case .PageSize(let size):
                query += "pageSize=\(size)"
            case .PageNumber(let number):
                query += "pageNumber=\(number)"
            case .FilterArray(let filters):
                query += "filter=\(filterStringFromFilters(filters) ?? "")"
            case .ExcludeArray(let excluded):
                query += "exclude=\(excludeStringFromExcludeOptions(excluded))"
            case .Deep(let deep):
                query += "deep=\(deep)"
            case .RelatedObjects(let related):
                query += "relatedObjects=\(related)"
            case .ReturnObject(let shouldReturn):
                query += "returnObject=\(shouldReturn)"
            case .Search(let searchString):
                query += "search=\(searchString)"
            }
            if index != options.count-1 {
                query += "&"
            }
        }
        return query
    }
    
    // MARK: GET
    
    /**
         Returns a single item.
         - parameters:
             - id: The item identity (id).
             - name: The object name.
             - options: Request options.
             - handler: The code to be executed once the request has finished.
    */
    public func getItemWithId(id: String, name: String, options: [BackandOption]?, handler: CompletionHandlerType) {
        var query: String? = nil
        if let options = options {
            query = queryStringFromOptions(options)
        }
        Alamofire.request(Router.ReadItem(name: name, id: id, query: query)).validate().responseJSON { response in
            switch response.result {
            case .Success:
                handler(Result.Success(response.result.value))
            case .Failure(let error):
                handler(Result.Failure(error))
            }
        }
    }
    
    /**
         Gets list of items with filter, sort and paging parameters.
         - parameters:
             - name: The object name.
             - options: Request options.
             - handler: The code to be executed once the request has finished.
    */
    public func getItemsWithName(name: String, options: [BackandOption]?, handler: CompletionHandlerType) {
        var query: String? = nil
        if let options = options {
            query = queryStringFromOptions(options)
        }
        Alamofire.request(Router.ReadItems(name: name, query: query)).validate().responseJSON { response in
            switch response.result {
            case .Success:
                handler(Result.Success(response.result.value))
            case .Failure(let error):
                handler(Result.Failure(error))
            }
        }
    }
    
    /**
        Executes a predefined query. You can define queries in your Backand dashboard.
        - parameters:
            - object: The object that you want to create.
            - name: The name of the query.
            - parameters: Query parameters.
            - handler: The code to be executed once the request has finished.
    */
    public func runQueryWithName(name: String, parameters: [String: AnyObject]?, handler: CompletionHandlerType) {
        Alamofire.request(Router.RunQuery(name: name, parameters: parameters)).validate().responseJSON { response in
            switch response.result {
            case .Success:
                handler(Result.Success(response.result.value))
            case .Failure(let error):
                handler(Result.Failure(error))
            }
        }
    }
    
    // MARK: POST
    
    /**
         Creates a new item.
         - parameters:
             - object: The object that you want to create.
             - name: The object name.
             - options: Request options.
             - handler: The code to be executed once the request has finished.
    */
    public func createItem(item: [String: AnyObject], name: String, options: [BackandOption]?, handler: CompletionHandlerType) {
        var query: String? = nil
        if let options = options {
            query = queryStringFromOptions(options)
        }
        Alamofire.request(Router.CreateItem(name: name, query: query, parameters: item)).validate().responseJSON { response in
            switch response.result {
            case .Success:
                handler(Result.Success(response.result.value))
            case .Failure(let error):
                handler(Result.Failure(error))
            }
        }
    }
    
    /**
        Executes an array of Action(s).
        - parameters:
            - actions: An array of Action(s).
            - handler: The code to be executed once the request has finished.
    */
    public func performActions(actions: [Action], handler: CompletionHandlerType) {
        var actionArray = [[String: AnyObject]]()
        for action in actions {
            actionArray.append(action.asObject())
        }
        Alamofire.request(Router.PerformActions(body: actionArray)).validate().responseJSON { response in
            switch response.result {
            case .Success:
                handler(Result.Success(response.result.value))
            case .Failure(let error):
                handler(Result.Failure(error))
            }
        }
    }
    
    // MARK: PUT
    
    /**
         Updates a single item.
         - parameters:
             - id: The item identity (id).
             - object: The object that you want to update.
             - name: The object name.
             - options: Request options.
             - handler: The code to be executed once the request has finished.
    */
    public func updateItemWithId(id: String, item: [String: AnyObject], name: String, options: [BackandOption]?, handler: CompletionHandlerType) {
        var query: String? = nil
        if let options = options {
            query = queryStringFromOptions(options)
        }
        Alamofire.request(Router.UpdateItem(name: name, id: id, query: query, parameters: item)).validate().responseJSON { response in
            switch response.result {
            case .Success:
                handler(Result.Success(response.result.value))
            case .Failure(let error):
                handler(Result.Failure(error))
            }
        }
    }
    
    // MARK: DELETE
    
    /**
         Deletes an item.
         - parameters:
             - id: The item identity (id).
             - name: The object name.
             - options: Request options.
             - handler: The code to be executed once the request has finished.
    */
    public func deleteItemWithId(id: String, name: String, handler: CompletionHandlerType) {
        Alamofire.request(Router.DeleteItem(name: name, id: id)).validate().responseJSON { response in
            switch response.result {
            case .Success:
                handler(Result.Success(response.result.value))
            case .Failure(let error):
                handler(Result.Failure(error))
            }
        }
    }
    
}
