//
// Copyright © 2022 osy. All rights reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

import Foundation
import AppKit
import ArgumentParser
import ScriptingBridge

@main
struct UTMCtl: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "utmctl",
        abstract: "CLI tool for controlling UTM virtual machines.",
        subcommands: [List.self, Status.self, Start.self, Suspend.self, Stop.self, Attach.self]
    )
}

/// Common interface for all subcommands
protocol UTMAPICommand: ParsableCommand {
    var environment: UTMCtl.EnvironmentOptions { get }
    
    func run(with application: UTMScriptingApplication) throws
}

extension UTMAPICommand {
    /// Entry point for all subcommands
    func run() throws {
        guard let app = SBApplication(url: utmAppUrl) else {
            throw UTMCtl.APIError.applicationNotFound
        }
        app.launchFlags = [.defaults, .andHide]
        app.delegate = UTMCtl.EventErrorHandler.shared
        let utmApp = app as UTMScriptingApplication
        if environment.hide {
            utmApp.setAutoTerminate!(false)
            if let windows = utmApp.windows!() as? [UTMScriptingWindow] {
                for window in windows {
                    if window.name == "UTM" {
                        window.close!()
                        break
                    }
                }
            }
        }
        try run(with: utmApp)
    }
    
    /// Get a virtual machine from an identifier
    /// - Parameters:
    ///   - identifier: Identifier
    ///   - application: Scripting bridge application
    /// - Returns: Virtual machine for identifier
    func virtualMachine(forIdentifier identifier: UTMCtl.VMIdentifier, in application: UTMScriptingApplication) throws -> UTMScriptingVirtualMachine {
        let list = application.virtualMachines!()
        return try withErrorsSilenced(application) {
            if let vm = list.object(withID: identifier.identifier) as? UTMScriptingVirtualMachine, vm.id!() == identifier.identifier {
                return vm
            } else if let vm = list.object(withName: identifier.identifier) as? UTMScriptingVirtualMachine, vm.name! == identifier.identifier {
                return vm
            } else {
                throw UTMCtl.APIError.virtualMachineNotFound
            }
        }
    }
    
    /// Find the path to UTM.app
    private var utmAppUrl: URL {
        if let executableURL = Bundle.main.executableURL {
            let utmURL = executableURL.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            if utmURL.lastPathComponent == "UTM.app" {
                return utmURL
            }
        }
        return URL(fileURLWithPath: "/Applications/UTM.app")
    }
    
    func withErrorsSilenced<Result>(_ application: UTMScriptingApplication, body: () throws -> Result) rethrows -> Result {
        let delegate = application.delegate
        application.delegate = nil
        let result = try body()
        application.delegate = delegate
        return result
    }
}

extension UTMCtl {
    @objc class EventErrorHandler: NSObject, SBApplicationDelegate {
        static let shared = EventErrorHandler()
        
        /// Error handler for scripting events
        /// - Parameters:
        ///   - event: Event that caused the error
        ///   - error: Error
        /// - Returns: nil
        func eventDidFail(_ event: UnsafePointer<AppleEvent>, withError error: Error) -> Any? {
            FileHandle.standardError.write("Error from event: \(error.localizedDescription)")
            if let user = (error as NSError).userInfo["ErrorString"] as? String {
                FileHandle.standardError.write(user)
            }
            return nil
        }
    }
}

extension UTMCtl {
    enum APIError: Error, LocalizedError {
        case applicationNotFound
        case virtualMachineNotFound
        
        var localizedDescription: String {
            switch self {
            case .applicationNotFound: return "Application not found."
            case .virtualMachineNotFound: return "Virtual machine not found."
            }
        }
    }
}

fileprivate extension UTMScriptingStatus {
    var asString: String {
        switch self {
        case .stopped: return "stopped"
        case .starting: return "starting"
        case .started: return "started"
        case .pausing: return "pausing"
        case .paused: return "paused"
        case .resuming: return "resuming"
        case .stopping: return "stopping"
        @unknown default: return "unknown"
        }
    }
}

extension UTMCtl {
    struct List: UTMAPICommand {
        static var configuration = CommandConfiguration(
            abstract: "Enumerate all registered virtual machines."
        )
        
        @OptionGroup var environment: EnvironmentOptions
        
        func run(with application: UTMScriptingApplication) throws {
            if let list = application.virtualMachines!() as? [UTMScriptingVirtualMachine] {
                printResponse(list)
            }
        }
        
        func printResponse(_ response: [UTMScriptingVirtualMachine]) {
            print("UUID                                 Status   Name")
            for entry in response {
                let status = entry.status!.asString.padding(toLength: 8, withPad: " ", startingAt: 0)
                print("\(entry.id!()) \(status) \(entry.name!)")
            }
        }
    }
}

extension UTMCtl {
    struct Status: UTMAPICommand {
        static var configuration = CommandConfiguration(
            abstract: "Query the status of a virtual machine."
        )
        
        @OptionGroup var environment: EnvironmentOptions
        
        @OptionGroup var identifer: VMIdentifier
        
        func run(with application: UTMScriptingApplication) throws {
            let vm = try virtualMachine(forIdentifier: identifer, in: application)
            printResponse(vm)
            
        }
        
        func printResponse(_ vm: UTMScriptingVirtualMachine) {
            print(vm.status!.asString)
        }
    }
}

extension UTMCtl {
    struct Start: UTMAPICommand {
        static var configuration = CommandConfiguration(
            abstract: "Start running a virtual machine."
        )
        
        @OptionGroup var environment: EnvironmentOptions
        
        @OptionGroup var identifer: VMIdentifier
        
        @Flag(name: .shortAndLong, help: "Attach to the first serial port after start.")
        var attach: Bool = false
        
        @Flag(help: "Run VM as a snapshot and do not save changes to disk.")
        var disposable: Bool = false
        
        func run(with application: UTMScriptingApplication) throws {
            let vm = try virtualMachine(forIdentifier: identifer, in: application)
            vm.startSaving!(!disposable)
            if attach {
                print("WARNING: attach command is not implemented yet!")
            }
        }
    }
}

extension UTMCtl {
    struct Suspend: UTMAPICommand {
        static var configuration = CommandConfiguration(
            abstract: "Suspend running a virtual machine."
        )
        
        @OptionGroup var environment: EnvironmentOptions
        
        @OptionGroup var identifer: VMIdentifier
        
        @Flag(name: .shortAndLong, help: "Save the VM state before suspending.")
        var saveState: Bool = false
        
        func run(with application: UTMScriptingApplication) throws {
            let vm = try virtualMachine(forIdentifier: identifer, in: application)
            vm.suspendSaving!(saveState)
        }
    }
}

extension UTMCtl {
    struct Stop: UTMAPICommand {
        static var configuration = CommandConfiguration(
            abstract: "Shuts down a virtual machine."
        )
        
        struct Style: ParsableArguments {
            @Flag(name: .long, help: "Force stop by sending a power off event (default)")
            var force: Bool = false
            
            @Flag(name: .long, help: "Force kill the VM process")
            var kill: Bool = false
            
            @Flag(name: .long, help: "Request power down from guest operating system")
            var request: Bool = false
            
            struct InvalidStyleError: LocalizedError {
                var errorDescription: String? {
                    "You can only specify one of: --force, --kill, or --request"
                }
            }
            
            mutating func validate() throws {
                let count = [force, kill, request].filter({ $0 }).count
                guard count <= 1 else {
                    throw InvalidStyleError()
                }
                if count == 0 {
                    force = true
                }
            }
        }
        
        @OptionGroup var environment: EnvironmentOptions
        
        @OptionGroup var identifer: VMIdentifier
        
        @OptionGroup var style: Style
        
        func run(with application: UTMScriptingApplication) throws {
            let vm = try virtualMachine(forIdentifier: identifer, in: application)
            var stopMethod: UTMScriptingStopMethod = .force
            if style.request {
                stopMethod = .request
            } else if style.force {
                stopMethod = .force
            } else if style.kill {
                stopMethod = .kill
            }
            vm.stopBy!(stopMethod)
        }
    }
}

extension UTMCtl {
    struct Attach: UTMAPICommand {
        static var configuration = CommandConfiguration(
            abstract: "Redirect the serial input/output to this terminal."
        )
        
        @OptionGroup var environment: EnvironmentOptions
        
        @OptionGroup var identifer: VMIdentifier
        
        @Option(help: "Index of the serial device to attach to.")
        var index: Int?
        
        func run(with application: UTMScriptingApplication) throws {
            let vm = try virtualMachine(forIdentifier: identifer, in: application)
            guard let serialPorts = vm.serialPorts!() as? [UTMScriptingSerialPort] else {
                return
            }
            for serialPort in serialPorts {
                if let index = index {
                    if index != serialPort.id!() {
                        continue
                    }
                }
                print("WARNING: attach command is not implemented yet!")
                if let interface = serialPort.interface, interface != .unavailable {
                    printResponse(serialPort)
                    return
                }
            }
        }
        
        func printResponse(_ serialPort: UTMScriptingSerialPort) {
            // TODO: spawn a terminal emulator
            if serialPort.interface == .ptty {
                print("PTTY: \(serialPort.address!)")
            } else if serialPort.interface == .tcp {
                print("TCP: \(serialPort.address!):\(serialPort.port!)")
            }
        }
    }
}

extension UTMCtl {
    struct VMIdentifier: ParsableArguments {
        @Argument(help: "Either the UUID or the complete name of the virtual machine.")
        var identifier: String
    }
    
    struct EnvironmentOptions: ParsableArguments {
        @Flag(name: .shortAndLong, help: "Show debug logging.")
        var debug: Bool = false
        
        @Flag(help: "Hide the main UTM window.")
        var hide: Bool = false
    }
}

private extension String {
    var asFileURL: URL {
        URL(fileURLWithPath: self, relativeTo: nil)
    }
}

extension FileHandle: TextOutputStream {
    private static var newLine = Data("\n".utf8)
    
    public func write(_ string: String) {
        let data = Data(string.utf8)
        self.write(data)
        self.write(Self.newLine)
    }
}
