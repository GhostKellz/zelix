///! Smart Contract utilities for both EVM and Hedera native contracts.
///! Provides high-level abstractions for contract deployment, calls, and queries.

const std = @import("std");
const model = @import("model.zig");
const tx = @import("tx.zig");
const abi = @import("abi.zig");

/// Contract type (EVM or Native Hedera)
pub const ContractType = enum {
    evm,          // Solidity/EVM contracts
    native_rust,  // Hedera native Rust contracts (WASM)
    native_go,    // Hedera native Go contracts
};

/// Smart contract instance
pub const Contract = struct {
    allocator: std.mem.Allocator,
    contract_id: model.ContractId,
    contract_type: ContractType,

    pub fn init(allocator: std.mem.Allocator, contract_id: model.ContractId, contract_type: ContractType) Contract {
        return .{
            .allocator = allocator,
            .contract_id = contract_id,
            .contract_type = contract_type,
        };
    }

    /// Call a contract function (EVM)
    pub fn callFunction(
        self: *Contract,
        client: anytype,
        function_signature: []const u8,
        params: []const abi.AbiValue,
        gas: u64,
    ) !model.TransactionReceipt {
        if (self.contract_type != .evm) return error.NotEvmContract;

        // Encode function call
        const call_data = try abi.encodeFunctionCall(
            self.allocator,
            function_signature,
            params,
        );
        defer self.allocator.free(call_data);

        // Create contract execute transaction
        var contract_tx = tx.ContractExecuteTransaction{
            .builder = .{},
        };

        _ = contract_tx.setContractId(self.contract_id);
        _ = contract_tx.setGas(gas);
        _ = contract_tx.setFunctionParameters(.{ .bytes = call_data });

        // Sign and execute
        const operator_key = client.operator_key orelse return error.NoOperatorKey;
        try contract_tx.sign(operator_key);

        return try contract_tx.execute(client, self.allocator);
    }

    /// Call a native Hedera contract function
    pub fn callNativeFunction(
        self: *Contract,
        client: anytype,
        function_name: []const u8,
        params: []const u8,
        gas: u64,
    ) !model.TransactionReceipt {
        if (self.contract_type == .evm) return error.NotNativeContract;

        var contract_tx = tx.ContractExecuteTransaction{
            .builder = .{},
        };

        _ = contract_tx.setContractId(self.contract_id);
        _ = contract_tx.setGas(gas);

        // For native contracts, encode function name + params
        var call_data: std.ArrayList(u8) = .{};
        defer call_data.deinit(self.allocator);

        try call_data.appendSlice(self.allocator, function_name);
        try call_data.append(self.allocator, 0); // null terminator
        try call_data.appendSlice(self.allocator, params);

        const data_owned = try call_data.toOwnedSlice(self.allocator);
        defer self.allocator.free(data_owned);

        _ = contract_tx.setFunctionParameters(.{ .bytes = data_owned });

        const operator_key = client.operator_key orelse return error.NoOperatorKey;
        try contract_tx.sign(operator_key);

        return try contract_tx.execute(client, self.allocator);
    }

    /// Query contract state (read-only)
    pub fn queryFunction(
        self: *Contract,
        client: anytype,
        function_signature: []const u8,
        params: []const abi.AbiValue,
        expected_return_types: []const abi.AbiType,
    ) ![]abi.AbiValue {
        if (self.contract_type != .evm) return error.NotEvmContract;

        // Encode function call
        const call_data = try abi.encodeFunctionCall(
            self.allocator,
            function_signature,
            params,
        );
        defer self.allocator.free(call_data);

        // Execute contract call query via mirror node
        const result = try client.mirror_client.contractCallQuery(
            self.contract_id,
            call_data,
        );
        defer self.allocator.free(result);

        // Decode result
        return try abi.decodeParameters(self.allocator, result, expected_return_types);
    }
};

/// Contract deployment helper
pub const ContractDeployer = struct {
    allocator: std.mem.Allocator,
    contract_type: ContractType,

    pub fn init(allocator: std.mem.Allocator, contract_type: ContractType) ContractDeployer {
        return .{
            .allocator = allocator,
            .contract_type = contract_type,
        };
    }

    /// Deploy an EVM contract from bytecode
    pub fn deployEvm(
        self: *ContractDeployer,
        client: anytype,
        bytecode: []const u8,
        constructor_params: []const abi.AbiValue,
        gas: u64,
        initial_balance: model.Hbar,
    ) !model.ContractId {
        if (self.contract_type != .evm) return error.NotEvmDeployment;

        // Encode constructor parameters
        const constructor_data = try abi.encodeParameters(self.allocator, constructor_params);
        defer self.allocator.free(constructor_data);

        // Combine bytecode + constructor params
        var deploy_data: std.ArrayList(u8) = .{};
        defer deploy_data.deinit(self.allocator);

        try deploy_data.appendSlice(self.allocator, bytecode);
        try deploy_data.appendSlice(self.allocator, constructor_data);

        const bytecode_with_constructor = try deploy_data.toOwnedSlice(self.allocator);
        defer self.allocator.free(bytecode_with_constructor);

        var create_tx = tx.ContractCreateTransaction{
            .builder = .{},
            .bytecode = bytecode_with_constructor,
            .gas = gas,
            .initial_balance = initial_balance,
        };

        const operator_key = client.operator_key orelse return error.NoOperatorKey;
        try create_tx.sign(operator_key);

        const receipt = try create_tx.execute(client, self.allocator);

        return receipt.contract_id orelse error.NoContractIdInReceipt;
    }

    /// Deploy a native Hedera contract (WASM)
    pub fn deployNative(
        self: *ContractDeployer,
        client: anytype,
        wasm_bytecode: []const u8,
        gas: u64,
        initial_balance: model.Hbar,
    ) !model.ContractId {
        if (self.contract_type == .evm) return error.NotNativeDeployment;

        var create_tx = tx.ContractCreateTransaction{
            .builder = .{},
            .bytecode = wasm_bytecode,
            .gas = gas,
            .initial_balance = initial_balance,
        };

        const operator_key = client.operator_key orelse return error.NoOperatorKey;
        try create_tx.sign(operator_key);

        const receipt = try create_tx.execute(client, self.allocator);

        return receipt.contract_id orelse error.NoContractIdInReceipt;
    }
};

/// Event log parser for contract events
pub const EventLog = struct {
    address: model.ContractId,
    topics: [][]const u8,
    data: []const u8,

    pub fn deinit(self: *EventLog, allocator: std.mem.Allocator) void {
        for (self.topics) |topic| {
            allocator.free(topic);
        }
        if (self.topics.len > 0) allocator.free(self.topics);
        if (self.data.len > 0) allocator.free(self.data);
    }

    /// Parse event log from transaction output
    pub fn parseFromOutput(allocator: std.mem.Allocator, output: []const u8) !EventLog {
        // Simplified parser - in production, parse actual Ethereum log format
        return .{
            .address = .{},
            .topics = &[_][]const u8{},
            .data = try allocator.dupe(u8, output),
        };
    }

    /// Decode event data using ABI
    pub fn decodeData(
        self: *const EventLog,
        allocator: std.mem.Allocator,
        expected_types: []const abi.AbiType,
    ) ![]abi.AbiValue {
        return try abi.decodeParameters(allocator, self.data, expected_types);
    }
};

/// Gas estimation utility
pub const GasEstimator = struct {
    /// Estimate gas for simple value transfer
    pub fn estimateTransfer() u64 {
        return 21_000; // Standard ETH transfer gas
    }

    /// Estimate gas for contract call (conservative estimate)
    pub fn estimateContractCall(data_size: usize) u64 {
        const base_gas: u64 = 21_000;
        const data_gas: u64 = @intCast(data_size * 68); // 68 gas per byte
        const execution_overhead: u64 = 30_000; // Conservative overhead

        return base_gas + data_gas + execution_overhead;
    }

    /// Estimate gas for contract deployment
    pub fn estimateContractDeployment(bytecode_size: usize) u64 {
        const base_gas: u64 = 32_000;
        const bytecode_gas: u64 = @intCast(bytecode_size * 200); // 200 gas per byte
        const initialization_overhead: u64 = 50_000;

        return base_gas + bytecode_gas + initialization_overhead;
    }
};
