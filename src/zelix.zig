//! Zelix: Hedera SDK for Zig
//!
//! This is the public API entrypoint for the Zelix Hedera SDK.
//! Import this module to access clients, queries, transactions, and core types.

const std = @import("std");

// Core types
pub const AccountId = @import("model.zig").AccountId;
pub const TokenId = @import("model.zig").TokenId;
pub const ContractId = @import("model.zig").ContractId;
pub const TopicId = @import("model.zig").TopicId;
pub const TransactionId = @import("model.zig").TransactionId;
pub const Hbar = @import("model.zig").Hbar;
pub const Timestamp = @import("model.zig").Timestamp;
pub const Network = @import("model.zig").Network;

// Client
pub const Client = @import("client.zig").Client;

// Crypto
pub const crypto = @import("crypto.zig");
pub const PrivateKey = crypto.PrivateKey;
pub const PublicKey = crypto.PublicKey;

// Queries
pub const AccountBalanceQuery = @import("query.zig").AccountBalanceQuery;
pub const AccountInfoQuery = @import("query.zig").AccountInfoQuery;
pub const AccountRecordsQuery = @import("query.zig").AccountRecordsQuery;
pub const TokenInfoQuery = @import("query.zig").TokenInfoQuery;
pub const TokenBalanceQuery = @import("query.zig").TokenBalanceQuery;
pub const ContractInfoQuery = @import("query.zig").ContractInfoQuery;
pub const ContractCallQuery = @import("query.zig").ContractCallQuery;
pub const TransactionReceiptQuery = @import("query.zig").TransactionReceiptQuery;

// Transactions
pub const CryptoTransferTransaction = @import("tx.zig").CryptoTransferTransaction;
pub const TopicMessageSubmitTransaction = @import("tx.zig").TopicMessageSubmitTransaction;
pub const AccountCreateTransaction = @import("tx.zig").AccountCreateTransaction;
pub const AccountUpdateTransaction = @import("tx.zig").AccountUpdateTransaction;
pub const AccountDeleteTransaction = @import("tx.zig").AccountDeleteTransaction;
pub const TokenCreateTransaction = @import("tx.zig").TokenCreateTransaction;
pub const TokenTransferTransaction = @import("tx.zig").TokenTransferTransaction;
pub const TokenAssociateTransaction = @import("tx.zig").TokenAssociateTransaction;
pub const TokenDissociateTransaction = @import("tx.zig").TokenDissociateTransaction;
pub const ContractCreateTransaction = @import("tx.zig").ContractCreateTransaction;
pub const ContractExecuteTransaction = @import("tx.zig").ContractExecuteTransaction;
pub const TransactionResponse = @import("model.zig").TransactionResponse;

// Mirror client
pub const MirrorClient = @import("mirror.zig").MirrorClient;
pub const AccountInfo = @import("mirror.zig").AccountInfo;
pub const TransactionInfo = @import("mirror.zig").TransactionInfo;
pub const TopicMessage = @import("mirror.zig").TopicMessage;

// Consensus client
pub const ConsensusClient = @import("consensus.zig").ConsensusClient;

// Block Streams
pub const BlockStreamClient = @import("block_stream.zig").BlockStreamClient;
pub const block_parser = @import("block_parser.zig");
