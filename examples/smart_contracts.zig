//! Smart Contract Operations Example
//!
//! This example demonstrates comprehensive smart contract operations using Zelix:
//! - Creating smart contracts with bytecode
//! - Executing contract functions with parameters
//! - Querying contract information and calling view functions
//! - EVM compatibility features

const std = @import("std");
const zelix = @import("zelix");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize client
    var client = try zelix.Client.init(allocator, .testnet);
    defer client.deinit();

    // Generate keys for contract admin
    const private_key = try zelix.crypto.PrivateKey.generate();
    const public_key = try private_key.toPublicKey();

    std.debug.print("=== Smart Contract Operations Example ===\n", .{});

    // 1. Create a Smart Contract
    std.debug.print("\n1. Creating Smart Contract...\n", .{});

    // Example bytecode (this would be compiled Solidity/Vyper in real usage)
    const contract_bytecode = "608060405234801561001057600080fd5b50d3801561001d57600080fd5b50d2801561002a57600080fd5b5061012f806100396000396000f3fe6080604052348015600f57600080fd5b506004361060285760003560e01c80636d4ce63c14602d575b600080fd5b60336047565b60408051918252519081900360200190f35b6000549056fea2646970667358221220b8a8a8a8a8a8a8a8a8a8a8a8a8a8a8a8a8a8a8a8a8a8a8a8a8a8a8a8a8a8a8a8a84736f6c63430006060033";

    var contract_create_tx = zelix.ContractCreateTransaction{};
    _ = contract_create_tx
        .setBytecode(contract_bytecode)
        .setAdminKey(public_key)
        .setGas(300_000)
        .setInitialBalance(zelix.Hbar.fromHbars(10))
        .setMemo("Example smart contract created with Zelix SDK");

    std.debug.print("Contract Create Transaction prepared\n", .{});

    // 2. Create Contract with Constructor Parameters
    std.debug.print("\n2. Creating Contract with Constructor Parameters...\n", .{});

    const constructor_params = zelix.ContractFunctionParameters.fromString("000000000000000000000000000000000000000000000000000000000000002a"); // uint256(42)

    var contract_with_params_tx = zelix.ContractCreateTransaction{};
    _ = contract_with_params_tx
        .setBytecode(contract_bytecode)
        .setConstructorParameters(constructor_params)
        .setGas(500_000)
        .setMemo("Contract with constructor parameters");

    std.debug.print("Contract Create with Constructor Parameters prepared\n", .{});

    // 3. Execute Contract Function
    std.debug.print("\n3. Preparing Contract Function Execution...\n", .{});

    const contract_id = zelix.ContractId.init(0, 0, 12345); // Would be from contract creation

    // Function call data (example: setValue(uint256) with value 100)
    const function_params = zelix.ContractFunctionParameters.fromString("552410770000000000000000000000000000000000000000000000000000000000000064"); // setValue(100)

    var contract_execute_tx = zelix.ContractExecuteTransaction{};
    _ = contract_execute_tx
        .setContractId(contract_id)
        .setGas(100_000)
        .setFunctionParameters(function_params)
        .setPayableAmount(zelix.Hbar.fromTinybars(1_000_000)); // 0.01 HBAR

    std.debug.print("Contract Execute Transaction prepared (calling setValue(100))\n", .{});

    // 4. Query Contract Information
    std.debug.print("\n4. Querying Contract Information...\n", .{});

    var contract_info_query = zelix.ContractInfoQuery{};
    _ = contract_info_query.setContractId(contract_id);

    // In real implementation:
    // const contract_info = try contract_info_query.execute(&client);
    // std.debug.print("Contract: {s}\n", .{contract_info.memo});
    // std.debug.print("Bytecode: {x}\n", .{std.fmt.fmtSliceHexLower(contract_info.bytecode)});

    std.debug.print("Contract Info Query prepared\n", .{});

    // 5. Call Contract View Function
    std.debug.print("\n5. Calling Contract View Function...\n", .{});

    // Function call data for getValue() view function
    const view_function_params = zelix.ContractFunctionParameters.fromString("6d4ce63c"); // getValue()

    var contract_call_query = zelix.ContractCallQuery{};
    _ = contract_call_query
        .setContractId(contract_id)
        .setGas(50_000)
        .setFunctionParameters(view_function_params);

    // In real implementation:
    // const result = try contract_call_query.execute(&client);
    // std.debug.print("Contract call result: {x}\n", .{std.fmt.fmtSliceHexLower(result.contract_call_result)});

    std.debug.print("Contract Call Query prepared (calling getValue())\n", .{});

    // 6. Execute Contract with EVM Address
    std.debug.print("\n6. Preparing Contract Execution with EVM Address...\n", .{});

    // Example EVM address (0x1234567890123456789012345678901234567890)
    const evm_address = "1234567890123456789012345678901234567890";

    var evm_contract_execute_tx = zelix.ContractExecuteTransaction{};
    _ = evm_contract_execute_tx
        .setContractId(zelix.ContractId.init(0, 0, 0)) // Use 0.0.0 for EVM addresses
        .setGas(200_000)
        .setFunctionParameters(function_params);

    // In real implementation, you would set the EVM address in the transaction
    // This demonstrates Hedera's EVM compatibility

    std.debug.print("EVM Contract Execute Transaction prepared (address: 0x{s})\n", .{evm_address});

    std.debug.print("\n=== All Smart Contract Operations Prepared Successfully ===\n", .{});
    std.debug.print("Note: In a real application, you would submit these transactions to the network\n", .{});
    std.debug.print("and wait for receipts to confirm successful execution.\n", .{});
    std.debug.print("\nEVM Compatibility: Zelix supports both native Hedera contracts and EVM-compatible\n", .{});
    std.debug.print("contracts deployed on Hedera Smart Contracts Service.\n", .{});
}
