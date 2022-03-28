//  Package: web3swift
//  Created by Alex Vlasov.
//  Copyright © 2018 Alex Vlasov. All rights reserved.
//
//  Support for EIP-1559 Transaction type by Mark Loit March 2022

import Foundation
import BigInt

public struct EIP1559Envelope: EIP2718Envelope {
    public let type: TransactionType = .eip1559

    // common parameters for any transaction
    public var nonce: BigUInt = 0
    public var chainID: BigUInt? {
        get { return internalChainID }
        // swiftlint:disable force_unwrapping
        set(newID) { if newID != nil { internalChainID = newID! } }
        // swiftlint:enable force_unwrapping
    }
    public var to: EthereumAddress
    public var value: BigUInt
    public var data: Data
    public var v: BigUInt
    public var r: BigUInt
    public var s: BigUInt

    // EIP-1559 specific parameters
    public var gasLimit: BigUInt
    public var maxPriorityFeePerGas: BigUInt
    public var maxFeePerGas: BigUInt
    public var accessList: [AccessListEntry] // from EIP-2930

    private var internalChainID: BigUInt

    // for CustomStringConvertible
    public var description: String {
        var toReturn = ""
        toReturn += "Type: " + String(describing: self.type) + "\n"
        toReturn += "chainID: " + String(describing: self.chainID) + "\n"
        toReturn += "Nonce: " + String(describing: self.nonce) + "\n"
        toReturn += "Gas limit: " + String(describing: self.gasLimit) + "\n"
        toReturn += "Max priority fee per gas: " + String(describing: self.maxPriorityFeePerGas) + "\n"
        toReturn += "Max fee per gas: " + String(describing: maxFeePerGas) + "\n"
        toReturn += "To: " + self.to.address + "\n"
        toReturn += "Value: " + String(describing: self.value) + "\n"
        toReturn += "Data: " + self.data.toHexString().addHexPrefix().lowercased() + "\n"
        toReturn += "Access List: " + String(describing: accessList) + "\n"
        toReturn += "v: " + String(self.v) + "\n"
        toReturn += "r: " + String(self.r) + "\n"
        toReturn += "s: " + String(self.s) + "\n"
        return toReturn
    }
}

extension EIP1559Envelope {
    private enum CodingKeys: String, CodingKey {
        case chainId
        case nonce
        case to
        case value
        case maxPriorityFeePerGas
        case maxFeePerGas
        case gasLimit
        case gas
        case data
        case input
        case accessList
        case v
        case r
        case s
    }

    public init?(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if !container.contains(.to) || !container.contains(.nonce) || !container.contains(.value) || !container.contains(.chainId) { return nil }
        if !container.contains(.data) && !container.contains(.input) { return nil }
        if !container.contains(.v) || !container.contains(.r) || !container.contains(.s) { return nil }

        // everything we need is present, so we should only have to throw from here
        self.internalChainID = try container.decodeHexIfPresent(to: BigUInt.self, key: .chainId) ?? 0
        self.nonce = try container.decodeHex(to: BigUInt.self, key: .nonce)

        let list = try? container.decode([AccessListEntry].self, forKey: .accessList)
        self.accessList = list ?? []

        let toString = try? container.decode(String.self, forKey: .to)
        switch toString {
        case nil, "0x", "0x0":
            self.to = EthereumAddress.contractDeploymentAddress()
        default:
            // the forced unwrap here is safe as we trap nil in the previous case
            // swiftlint:disable force_unwrapping
            guard let ethAddr = EthereumAddress(toString!) else { throw Web3Error.dataError }
            // swiftlint:enable force_unwrapping
            self.to = ethAddr
        }
        self.value = try container.decodeHexIfPresent(to: BigUInt.self, key: .value) ?? 0
        self.maxPriorityFeePerGas = try container.decodeHexIfPresent(to: BigUInt.self, key: .maxPriorityFeePerGas) ?? 0
        self.maxFeePerGas = try container.decodeHexIfPresent(to: BigUInt.self, key: .maxFeePerGas) ?? 0
        self.gasLimit = try container.decodeHexIfPresent(to: BigUInt.self, key: .gas) ?? container.decodeHexIfPresent(to: BigUInt.self, key: .gasLimit) ?? 0

        self.data = try container.decodeHexIfPresent(to: Data.self, key: .input) ?? container.decodeHex(to: Data.self, key: .data)
        self.v = try container.decodeHex(to: BigUInt.self, key: .v)
        self.r = try container.decodeHex(to: BigUInt.self, key: .r)
        self.s = try container.decodeHex(to: BigUInt.self, key: .s)
    }

    private enum RlpKey: Int {
        case chainId
        case nonce
        case maxPriorityFeePerGas
        case maxFeePerGas
        case gasLimit
        case destination
        case amount
        case data
        case accessList
        case sig_v
        case sig_r
        case sig_s
        case total // not a real entry, used to auto-size based on number of keys
    }

    public init?(rawValue: Data) {
        // pop the first byte from the stream [EIP-2718]
        let typeByte: UInt8 = rawValue.first ?? 0 // can't decode if we're the wrong type
        if typeByte != self.type.rawValue { return nil }

        guard let totalItem = RLP.decode(rawValue.dropFirst(1)) else { return nil }
        guard let rlpItem = totalItem[0] else { return nil }
        if rlpItem.count != RlpKey.total.rawValue { return nil }

        // we've validated the item count, so rlpItem[keyName] is guaranteed to return something not nil
        // swiftlint:disable force_unwrapping
        guard let chainData = rlpItem[RlpKey.chainId.rawValue]!.data else { return nil }
        guard let nonceData = rlpItem[RlpKey.nonce.rawValue]!.data else { return nil }
        guard let maxPriorityData = rlpItem[RlpKey.maxPriorityFeePerGas.rawValue]!.data else { return nil }
        guard let maxFeeData = rlpItem[RlpKey.maxFeePerGas.rawValue]!.data else { return nil }
        guard let gasLimitData = rlpItem[RlpKey.gasLimit.rawValue]!.data else { return nil }
        guard let valueData = rlpItem[RlpKey.amount.rawValue]!.data else { return nil }
        guard let transactionData = rlpItem[RlpKey.data.rawValue]!.data else { return nil }
        guard let vData = rlpItem[RlpKey.sig_v.rawValue]!.data else { return nil }
        guard let rData = rlpItem[RlpKey.sig_r.rawValue]!.data else { return nil }
        guard let sData = rlpItem[RlpKey.sig_s.rawValue]!.data else { return nil }
        // swiftlint:enable force_unwrapping

        self.internalChainID = BigUInt(chainData)
        self.nonce = BigUInt(nonceData)
        self.maxPriorityFeePerGas = BigUInt(maxPriorityData)
        self.maxFeePerGas = BigUInt(maxFeeData)
        self.gasLimit = BigUInt(gasLimitData)
        self.value = BigUInt(valueData)
        self.data = transactionData
        self.v = BigUInt(vData)
        self.r = BigUInt(rData)
        self.s = BigUInt(sData)

        // swiftlint:disable force_unwrapping
        switch rlpItem[RlpKey.destination.rawValue]!.content {
            // swiftlint:enable force_unwrapping
        case .noItem:
            self.to = EthereumAddress.contractDeploymentAddress()
        case .data(let addressData):
            if addressData.count == 0 {
                self.to = EthereumAddress.contractDeploymentAddress()
            } else if addressData.count == 20 {
                guard let addr = EthereumAddress(addressData) else { return nil }
                self.to = addr
            } else { return nil }
        case .list:
            return nil
        }

        // swiftlint:disable force_unwrapping
        switch rlpItem[RlpKey.accessList.rawValue]!.content {
            // swiftlint:enable force_unwrapping
        case .noItem:
            self.accessList = []
        case .data:
            return nil
        case .list:
            // decode the list here
            // swiftlint:disable force_unwrapping
            let accessData = rlpItem[RlpKey.accessList.rawValue]!
            // swiftlint:enable force_unwrapping
            let itemCount = accessData.count ?? 0
            var newList: [AccessListEntry] = []
            for index in 0...(itemCount - 1) {
                guard let itemData = accessData[index] else { return nil }
                guard let newItem = AccessListEntry(rlpItem: itemData)  else { return nil }
                newList.append(newItem)
            }
            self.accessList = newList
        }
    }

    public init(to: EthereumAddress, nonce: BigUInt? = nil,
                chainID: BigUInt? = nil, value: BigUInt? = nil, data: Data,
                v: BigUInt = 1, r: BigUInt = 0, s: BigUInt = 0,
                options: TransactionOptions? = nil) {
        self.to = to
        self.nonce = nonce ?? options?.resolveNonce(0) ?? 0
        self.internalChainID = chainID ?? 0
        self.value = value ?? options?.value ?? 0
        self.data = data
        self.v = v
        self.r = r
        self.s = s
        // decode gas options, if present
        self.maxPriorityFeePerGas = options?.resolveMaxPriorityFeePerGas(0) ?? 0
        self.maxFeePerGas = options?.resolveMaxFeePerGas(0) ?? 0
        self.gasLimit = options?.resolveGasLimit(0) ?? 0
        // get teh access list, if present
        self.accessList = options?.accessList ?? []
    }

    // memberwise
    public init(to: EthereumAddress, nonce: BigUInt = 0,
                chainID: BigUInt = 0, value: BigUInt = 0, data: Data,
                maxPriorityFeePerGas: BigUInt = 0, maxFeePerGas: BigUInt = 0, gasLimit: BigUInt = 0,
                accessList: [AccessListEntry]? = nil,
                v: BigUInt = 1, r: BigUInt = 0, s: BigUInt = 0) {
        self.to = to
        self.nonce = nonce
        self.internalChainID = chainID
        self.value = value
        self.data = data
        self.maxPriorityFeePerGas = maxPriorityFeePerGas
        self.maxFeePerGas = maxFeePerGas
        self.gasLimit = gasLimit
        self.accessList = accessList ?? []
        self.v = v
        self.r = r
        self.s = s
    }

    public mutating func applyOptions(_ options: TransactionOptions) {
        // type cannot be changed here, and is ignored
        self.nonce = options.resolveNonce(self.nonce)
        self.maxPriorityFeePerGas = options.resolveMaxPriorityFeePerGas(self.maxPriorityFeePerGas)
        self.maxFeePerGas = options.resolveMaxFeePerGas(self.maxFeePerGas)
        self.gasLimit = options.resolveGasLimit(self.gasLimit)
        // swiftlint:disable force_unwrapping
        if options.value != nil { self.value = options.value! }
        if options.to != nil { self.to = options.to! }
        if options.accessList != nil { self.accessList = options.accessList! }
        // swiftlint:enable force_unwrapping
    }

    public func getOptions() -> TransactionOptions {
        var options = TransactionOptions()
        options.nonce = .manual(self.nonce)
        options.maxPriorityFeePerGas = .manual(self.maxPriorityFeePerGas)
        options.maxFeePerGas = .manual(self.maxFeePerGas)
        options.gasLimit = .manual(self.gasLimit)
        options.value = self.nonce
        options.to = self.to
        options.accessList = self.accessList
        return options
    }

    public func encodeFor(_ type: EncodeType = .transaction) -> Data? {
        let fields: [AnyObject]
        var list: [AnyObject] = []

        for listEntry in self.accessList {
            let encoded = listEntry.encodeAsList()
            list.append(encoded as AnyObject)
        }

        switch type {
        case .transaction: fields = [internalChainID, nonce, maxPriorityFeePerGas, maxFeePerGas, gasLimit, to.addressData, value, data, list, v, r, s] as [AnyObject]
        case .signature: fields = [internalChainID, nonce, maxPriorityFeePerGas, maxFeePerGas, gasLimit, to.addressData, value, data, list] as [AnyObject]
        }
        guard var result = RLP.encode(fields) else { return nil }
        result.insert(UInt8(self.type.rawValue), at: 0)
        return result
    }

    public func encodeAsDictionary(from: EthereumAddress? = nil) -> TransactionParameters? {
        var toString: String?
        switch self.to.type {
        case .normal:
            toString = self.to.address.lowercased()
        case .contractDeployment:
            break
        }
        var params = TransactionParameters(from: from?.address.lowercased(), to: toString)
        let typeEncoding = String(UInt8(self.type.rawValue), radix: 16).addHexPrefix()
        params.type = typeEncoding
        let chainEncoding = self.internalChainID.abiEncode(bits: 256)
        params.chainID = chainEncoding?.toHexString().addHexPrefix().stripLeadingZeroes()
        var accessEncoding: [TransactionParameters.AccessListEntry] = []
        for listEntry in self.accessList {
            guard let encoded = listEntry.encodeAsDictionary() else { return nil }
            accessEncoding.append(encoded)
        }
        params.accessList = accessEncoding
        let gasEncoding = self.gasLimit.abiEncode(bits: 256)
        params.gas = gasEncoding?.toHexString().addHexPrefix().stripLeadingZeroes()
        let maxFeeEncoding = self.maxFeePerGas.abiEncode(bits: 256)
        params.maxFeePerGas = maxFeeEncoding?.toHexString().addHexPrefix().stripLeadingZeroes()
        let maxPriorityEncoding = self.maxPriorityFeePerGas.abiEncode(bits: 256)
        params.maxPriorityFeePerGas = maxPriorityEncoding?.toHexString().addHexPrefix().stripLeadingZeroes()
        let valueEncoding = self.value.abiEncode(bits: 256)
        params.value = valueEncoding?.toHexString().addHexPrefix().stripLeadingZeroes()
        if self.data != Data() {
            params.data = self.data.toHexString().addHexPrefix()
        } else {
            params.data = "0x"
        }
        return params
    }
}
