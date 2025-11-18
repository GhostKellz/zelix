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
pub const FileId = @import("model.zig").FileId;
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

// Transactions - Account
pub const CryptoTransferTransaction = @import("tx.zig").CryptoTransferTransaction;
pub const AccountCreateTransaction = @import("tx.zig").AccountCreateTransaction;
pub const AccountUpdateTransaction = @import("tx.zig").AccountUpdateTransaction;
pub const AccountDeleteTransaction = @import("tx.zig").AccountDeleteTransaction;

// Transactions - Topic/Consensus
pub const TopicMessageSubmitTransaction = @import("tx.zig").TopicMessageSubmitTransaction;

// Transactions - Token/NFT (HTS)
pub const token_tx = @import("token_tx.zig");
pub const TokenCreateTransaction = token_tx.TokenCreateTransaction;
pub const TokenMintTransaction = token_tx.TokenMintTransaction;
pub const TokenBurnTransaction = token_tx.TokenBurnTransaction;
pub const TokenAssociateTransaction = token_tx.TokenAssociateTransaction;
pub const TokenDissociateTransaction = token_tx.TokenDissociateTransaction;
pub const TokenUpdateTransaction = token_tx.TokenUpdateTransaction;
pub const TokenDeleteTransaction = token_tx.TokenDeleteTransaction;
pub const TokenWipeTransaction = token_tx.TokenWipeTransaction;
pub const TokenFreezeTransaction = token_tx.TokenFreezeTransaction;
pub const TokenUnfreezeTransaction = token_tx.TokenUnfreezeTransaction;
pub const TokenPauseTransaction = token_tx.TokenPauseTransaction;
pub const TokenUnpauseTransaction = token_tx.TokenUnpauseTransaction;

// Transactions - File Service (HFS)
pub const file_tx = @import("file_tx.zig");
pub const FileCreateTransaction = file_tx.FileCreateTransaction;
pub const FileAppendTransaction = file_tx.FileAppendTransaction;
pub const FileUpdateTransaction = file_tx.FileUpdateTransaction;
pub const FileDeleteTransaction = file_tx.FileDeleteTransaction;

// Transactions - Schedule Service
pub const schedule_tx = @import("schedule_tx.zig");
pub const ScheduleCreateTransaction = schedule_tx.ScheduleCreateTransaction;
pub const ScheduleSignTransaction = schedule_tx.ScheduleSignTransaction;
pub const ScheduleDeleteTransaction = schedule_tx.ScheduleDeleteTransaction;

// Transactions - Smart Contracts
pub const contract_tx = @import("contract_tx.zig");
pub const ContractCreateTransaction = contract_tx.ContractCreateTransaction;
pub const ContractExecuteTransaction = contract_tx.ContractExecuteTransaction;
pub const ContractUpdateTransaction = contract_tx.ContractUpdateTransaction;
pub const ContractDeleteTransaction = contract_tx.ContractDeleteTransaction;

// Transaction response
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

// Smart Contracts (EVM + Native)
pub const abi = @import("abi.zig");
pub const contract = @import("contract.zig");
pub const Contract = contract.Contract;
pub const ContractDeployer = contract.ContractDeployer;
pub const EventLog = contract.EventLog;
pub const GasEstimator = contract.GasEstimator;

// Performance & Infrastructure
pub const compression = @import("compression.zig");
pub const GzipDecompressor = compression.GzipDecompressor;
pub const connection_pool = @import("connection_pool.zig");
pub const ConnectionPool = connection_pool.ConnectionPool;
pub const async_io = @import("async_io.zig");
pub const AsyncTask = async_io.AsyncTask;
pub const Executor = async_io.Executor;
pub const Channel = async_io.Channel;

// Web3 Compatibility
pub const eip155 = @import("eip155.zig");
pub const Eip155Transaction = eip155.Eip155Transaction;
pub const Eip155Signature = eip155.Eip155Signature;
pub const web3_rpc = @import("web3_rpc.zig");
pub const Web3RpcClient = web3_rpc.Web3RpcClient;
pub const metamask = @import("metamask.zig");
pub const MetaMaskProvider = metamask.MetaMaskProvider;
pub const HederaChainParams = metamask.HederaChainParams;

// Contract Verification
pub const contract_verification = @import("contract_verification.zig");
pub const ContractVerifier = contract_verification.ContractVerifier;
pub const SourcifyVerifier = contract_verification.SourcifyVerifier;
