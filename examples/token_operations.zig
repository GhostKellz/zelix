//! Token Operations Example
//!
//! This example demonstrates comprehensive token operations using Zelix:
//! - Creating fungible and non-fungible tokens
//! - Token transfers and NFT transfers
//! - Token association and dissociation
//! - Querying token information and balances

const std = @import("std");
const zelix = @import("zelix");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize client
    var client = try zelix.Client.initFromEnv(allocator);
    defer client.deinit();

    // Generate keys for treasury account
    const private_key = try zelix.crypto.PrivateKey.generate();
    const public_key = try private_key.toPublicKey();

    // Create treasury account first
    const treasury_account_id = zelix.AccountId.init(0, 0, 12345); // In real app, this would be created

    std.debug.print("=== Token Operations Example ===\n", .{});

    // 1. Create a Fungible Token
    std.debug.print("\n1. Creating Fungible Token...\n", .{});

    var token_create_tx = zelix.TokenCreateTransaction.init(allocator);
    defer token_create_tx.deinit();

    _ = token_create_tx
        .setName("Zelix Example Token")
        .setSymbol("ZEXT")
        .setDecimals(8)
        .setInitialSupply(1_000_000)
        .setTreasuryAccountId(treasury_account_id)
        .setAdminKey(public_key)
        .setSupplyKey(public_key)
        .setMemo("Example token created with Zelix SDK");

    // In a real implementation, you would:
    // - Set transaction ID
    // - Freeze the transaction
    // - Sign with private key
    // - Submit to network
    // - Get receipt

    std.debug.print("Token Create Transaction prepared\n", .{});

    // 2. Create an NFT Collection
    std.debug.print("\n2. Creating NFT Collection...\n", .{});

    var nft_create_tx = zelix.TokenCreateTransaction.init(allocator);
    defer nft_create_tx.deinit();

    _ = nft_create_tx
        .setName("Zelix Example NFT")
        .setSymbol("ZEXNFT")
        .setTokenType(.non_fungible_unique)
        .setTreasuryAccountId(treasury_account_id)
        .setAdminKey(public_key)
        .setSupplyKey(public_key)
        .setMemo("Example NFT collection created with Zelix SDK");

    std.debug.print("NFT Create Transaction prepared\n", .{});

    // 3. Token Transfer Example
    std.debug.print("\n3. Preparing Token Transfer...\n", .{});

    const token_id = zelix.TokenId.init(0, 0, 56789); // Would be from token creation
    const recipient_account_id = zelix.AccountId.init(0, 0, 98765);

    var token_transfer_tx = zelix.TokenTransferTransaction.init(allocator);
    defer token_transfer_tx.deinit();

    try token_transfer_tx.addTokenTransfer(token_id, treasury_account_id, -1000); // Send 1000 tokens
    try token_transfer_tx.addTokenTransfer(token_id, recipient_account_id, 1000); // Receive 1000 tokens

    std.debug.print("Token Transfer Transaction prepared (1000 tokens)\n", .{});

    // 4. NFT Transfer Example
    std.debug.print("\n4. Preparing NFT Transfer...\n", .{});

    const nft_id = zelix.TokenId.init(0, 0, 11111); // Would be from NFT creation
    const nft_sender = treasury_account_id;
    const nft_receiver = recipient_account_id;
    const serial_number = 1;

    var nft_transfer_tx = zelix.TokenTransferTransaction.init(allocator);
    defer nft_transfer_tx.deinit();

    try nft_transfer_tx.addNftTransfer(nft_id, nft_sender, nft_receiver, serial_number);

    std.debug.print("NFT Transfer Transaction prepared (serial #{d})\n", .{serial_number});

    // 5. Token Association Example
    std.debug.print("\n5. Preparing Token Association...\n", .{});

    var token_associate_tx = zelix.TokenAssociateTransaction.init(allocator);
    defer token_associate_tx.deinit();

    const account_to_associate = recipient_account_id;
    _ = token_associate_tx.setAccountId(account_to_associate);
    try token_associate_tx.addTokenId(token_id);

    std.debug.print("Token Association Transaction prepared\n", .{});

    // 6. Query Token Information
    std.debug.print("\n6. Querying Token Information...\n", .{});

    var token_info_query = zelix.TokenInfoQuery{};
    _ = token_info_query.setTokenId(token_id);

    // In real implementation:
    // const token_info = try token_info_query.execute(&client);
    // std.debug.print("Token: {s} ({s})\n", .{token_info.name, token_info.symbol});

    std.debug.print("Token Info Query prepared\n", .{});

    // 7. Query Token Balances
    std.debug.print("\n7. Querying Token Balances...\n", .{});

    var token_balance_query = zelix.TokenBalanceQuery{};
    _ = token_balance_query.setAccountId(treasury_account_id);

    // In real implementation:
    // const balances = try token_balance_query.execute(&client);
    // for (balances.balances) |balance| {
    //     std.debug.print("Token {d}.{d}.{d}: {d} units\n", .{
    //         balance.token_id.shard, balance.token_id.realm, balance.token_id.num, balance.balance
    //     });
    // }

    std.debug.print("Token Balance Query prepared\n", .{});

    // 8. Token Dissociation Example
    std.debug.print("\n8. Preparing Token Dissociation...\n", .{});

    var token_dissociate_tx = zelix.TokenDissociateTransaction.init(allocator);
    defer token_dissociate_tx.deinit();

    _ = token_dissociate_tx.setAccountId(account_to_associate);
    try token_dissociate_tx.addTokenId(token_id);

    std.debug.print("Token Dissociation Transaction prepared\n", .{});

    std.debug.print("\n=== All Token Operations Prepared Successfully ===\n", .{});
    std.debug.print("Note: In a real application, you would submit these transactions to the network\n", .{});
    std.debug.print("and wait for receipts to confirm successful execution.\n", .{});
}
