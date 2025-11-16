//! Topic Message Submission Example
//! Demonstrates building and signing a topic message submit transaction.

const std = @import("std");
const zelix = @import("zelix");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const topic_id = zelix.TopicId.init(0, 0, 7001);
    const node_account = zelix.AccountId.init(0, 0, 3);

    var tx = zelix.TopicMessageSubmitTransaction.init(allocator);
    defer tx.deinit();

    tx.setNodeAccountId(node_account);
    tx.setMemo("demo topic message");
    tx.setMaxTransactionFee(zelix.Hbar.fromTinybars(100_000));
    try tx.setTopicId(topic_id);
    try tx.setMessage("Hello from Zelix!");
    try tx.freeze();

    // In production load a persisted operator key
    const private_key = zelix.crypto.PrivateKey.generateEd25519();
    try tx.sign(private_key);

    const bytes = try tx.toBytes();
    defer allocator.free(bytes);

    std.debug.print("topic message payload size: {d} bytes\n", .{bytes.len});
    std.debug.print("first 16 bytes: {any}\n", .{bytes[0..@min(bytes.len, 16)]});

    // To submit on a real network call client.consensus_client.submitTopicMessage(&tx)
    // or client.submitTopicMessage(&tx) after configuring a Zelix Client instance.
}
