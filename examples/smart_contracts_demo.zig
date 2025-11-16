const std = @import("std");
const zelix = @import("zelix");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("\n=== Zelix Smart Contract Examples ===\n\n", .{});

    // Initialize client
    var client = try zelix.Client.init(allocator, .testnet);
    defer client.deinit();

    // Example 1: Gas Estimation
    std.debug.print("=== Example 1: Gas Estimation ===\n", .{});

    const transfer_gas = zelix.GasEstimator.estimateTransfer();
    std.debug.print("Estimated gas for transfer: {d}\n", .{transfer_gas});

    const call_data_size = 68; // Example: 4 bytes selector + 64 bytes params
    const call_gas = zelix.GasEstimator.estimateContractCall(call_data_size);
    std.debug.print("Estimated gas for contract call: {d}\n", .{call_gas});

    const bytecode_size = 5000;
    const deploy_gas = zelix.GasEstimator.estimateContractDeployment(bytecode_size);
    std.debug.print("Estimated gas for deployment: {d}\n", .{deploy_gas});

    // Example 2: ABI Encoding/Decoding
    std.debug.print("\n=== Example 2: ABI Encoding/Decoding ===\n", .{});

    const encode_params = [_]zelix.abi.AbiValue{
        zelix.abi.helpers.uint256(42),
        zelix.abi.helpers.bool_value(true),
        try zelix.abi.helpers.string_value(allocator, "hello"),
    };
    defer {
        var mutable_params = encode_params;
        mutable_params[2].deinit(allocator);
    }

    const encoded = try zelix.abi.encodeParameters(allocator, &encode_params);
    defer allocator.free(encoded);

    std.debug.print("ABI encoded {d} params into {d} bytes\n", .{
        encode_params.len,
        encoded.len,
    });

    // Decode parameters
    const decode_types = [_]zelix.abi.AbiType{
        .uint256,
        .bool_type,
        .string,
    };

    const decoded = try zelix.abi.decodeParameters(allocator, encoded, &decode_types);
    defer {
        for (decoded) |*param| {
            param.deinit(allocator);
        }
        allocator.free(decoded);
    }

    std.debug.print("Decoded {d} parameters:\n", .{decoded.len});
    std.debug.print("  uint256: {d}\n", .{decoded[0].uint256});
    std.debug.print("  bool: {}\n", .{decoded[1].bool_value});
    std.debug.print("  string: {s}\n", .{decoded[2].string_value});

    // Example 3: Contract Types
    std.debug.print("\n=== Example 3: Contract Support ===\n", .{});

    std.debug.print("Supported contract types:\n", .{});
    std.debug.print("  - EVM (Solidity) contracts\n", .{});
    std.debug.print("  - Native Hedera Rust contracts (WASM)\n", .{});
    std.debug.print("  - Native Hedera Go contracts\n", .{});

    std.debug.print("\n All smart contract examples completed!\n", .{});
}
