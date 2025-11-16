///! MetaMask wallet integration for Web3 compatibility.
///! Provides utilities for MetaMask connection and signing.

const std = @import("std");
const mem = std.mem;
const web3_rpc = @import("web3_rpc.zig");
const eip155 = @import("eip155.zig");

/// MetaMask connection state
pub const MetaMaskProvider = struct {
    allocator: mem.Allocator,
    chain_id: u64,
    selected_address: ?[20]u8,
    connected: bool,

    pub fn init(allocator: mem.Allocator, chain_id: u64) MetaMaskProvider {
        return .{
            .allocator = allocator,
            .chain_id = chain_id,
            .selected_address = null,
            .connected = false,
        };
    }

    pub fn deinit(self: *MetaMaskProvider) void {
        _ = self;
    }

    /// Request account access (eth_requestAccounts)
    pub fn requestAccounts(self: *MetaMaskProvider) ![][20]u8 {
        // In browser environment, this would trigger MetaMask popup
        // For now, return mock address
        self.connected = true;
        const mock_address: [20]u8 = [_]u8{0} ** 20;
        self.selected_address = mock_address;

        var accounts = try self.allocator.alloc([20]u8, 1);
        accounts[0] = mock_address;
        return accounts;
    }

    /// Get current accounts
    pub fn getAccounts(self: *MetaMaskProvider) !?[][20]u8 {
        if (!self.connected or self.selected_address == null) {
            return null;
        }

        var accounts = try self.allocator.alloc([20]u8, 1);
        accounts[0] = self.selected_address.?;
        return accounts;
    }

    /// Request chain switch (wallet_switchEthereumChain)
    pub fn switchChain(self: *MetaMaskProvider, chain_id: u64) !void {
        self.chain_id = chain_id;
    }

    /// Add custom chain (wallet_addEthereumChain)
    pub fn addChain(self: *MetaMaskProvider, params: AddChainParams) !void {
        _ = self;
        _ = params;
        // In production: validate and add chain to MetaMask
    }

    /// Sign message (personal_sign)
    pub fn signMessage(self: *MetaMaskProvider, message: []const u8) ![]u8 {
        _ = message;
        if (!self.connected) return error.NotConnected;

        // In production: request signature from MetaMask
        // For now, return mock signature
        const signature = try self.allocator.alloc(u8, 65);
        @memset(signature, 0);
        return signature;
    }

    /// Sign typed data (eth_signTypedData_v4)
    pub fn signTypedData(self: *MetaMaskProvider, typed_data: TypedData) ![]u8 {
        if (!self.connected) return error.NotConnected;

        _ = typed_data;
        // In production: request EIP-712 signature from MetaMask
        const signature = try self.allocator.alloc(u8, 65);
        @memset(signature, 0);
        return signature;
    }

    /// Send transaction (eth_sendTransaction)
    pub fn sendTransaction(self: *MetaMaskProvider, params: TransactionParams) ![]u8 {
        if (!self.connected) return error.NotConnected;

        _ = params;
        // In production: request transaction signing and send
        const tx_hash = try self.allocator.alloc(u8, 32);
        @memset(tx_hash, 0);
        return tx_hash;
    }

    pub const AddChainParams = struct {
        chain_id: []const u8,
        chain_name: []const u8,
        native_currency: struct {
            name: []const u8,
            symbol: []const u8,
            decimals: u8,
        },
        rpc_urls: [][]const u8,
        block_explorer_urls: ?[][]const u8 = null,
        icon_urls: ?[][]const u8 = null,
    };

    pub const TypedData = struct {
        types: std.json.Value,
        primary_type: []const u8,
        domain: std.json.Value,
        message: std.json.Value,
    };

    pub const TransactionParams = struct {
        from: [20]u8,
        to: ?[20]u8,
        value: ?[]const u8 = null,
        data: ?[]const u8 = null,
        gas: ?[]const u8 = null,
        gas_price: ?[]const u8 = null,
    };
};

/// Hedera chain parameters for MetaMask
pub const HederaChainParams = struct {
    /// Hedera Mainnet
    pub const mainnet = MetaMaskProvider.AddChainParams{
        .chain_id = "0x127", // 295
        .chain_name = "Hedera Mainnet",
        .native_currency = .{
            .name = "HBAR",
            .symbol = "HBAR",
            .decimals = 8,
        },
        .rpc_urls = &[_][]const u8{
            "https://mainnet.hashio.io/api",
        },
        .block_explorer_urls = &[_][]const u8{
            "https://hashscan.io/mainnet",
        },
        .icon_urls = null,
    };

    /// Hedera Testnet
    pub const testnet = MetaMaskProvider.AddChainParams{
        .chain_id = "0x128", // 296
        .chain_name = "Hedera Testnet",
        .native_currency = .{
            .name = "HBAR",
            .symbol = "HBAR",
            .decimals = 8,
        },
        .rpc_urls = &[_][]const u8{
            "https://testnet.hashio.io/api",
        },
        .block_explorer_urls = &[_][]const u8{
            "https://hashscan.io/testnet",
        },
        .icon_urls = null,
    };
};
