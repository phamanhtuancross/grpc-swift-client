//
//  FileGenerator.swift
//  protoc-gen-swiftgrpc-client
//
//  Created by Kyohei Ito on 2018/08/10.
//

import SwiftProtobufPluginLibrary

final class FileGenerator {
    private let namer: SwiftProtobufNamer
    private let fileDescriptor: FileDescriptor
    private let generatorOptions: GeneratorOptions

    var outputFilename: String {
        let ext = ".grpc.client.swift"
        let pathParts = splitPath(pathname: fileDescriptor.name)
        return pathParts.dir + pathParts.base + ext
    }

    init(_ file: FileDescriptor, options: GeneratorOptions) {
        self.fileDescriptor = file
        self.generatorOptions = options
        self.namer = SwiftProtobufNamer(currentFile: file, protoFileToModuleMappings: ProtoFileToModuleMappings())
    }
}

extension FileGenerator {
    func generateOutputFile(printer p: inout CodePrinter) {
        p.println("""
            //
            // DO NOT EDIT.
            //
            // Generated by the protocol buffer compiler.
            // Source: \(fileDescriptor.name)
            //
            """)

        for moduleName in ["Foundation", "SwiftGRPCClient", "SwiftProtobuf"] {
            p.println("import \(moduleName)")
        }
        p.println()

        for service in fileDescriptor.services {
            ServiceGenerator(service: service, generatorOptions: generatorOptions, namer: namer).generateService(printer: &p)
        }
    }
}