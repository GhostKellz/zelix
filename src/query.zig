//! Query builders for read operations

const std = @import("std");
const model = @import("model.zig");
const client_mod = @import("client.zig");

pub const AccountBalance = struct {
    hbars: model.Hbar,
};

pub const AccountBalanceQuery = struct {
    account_id: ?model.AccountId = null,

    pub fn setAccountId(self: *AccountBalanceQuery, account_id: model.AccountId) *AccountBalanceQuery {
        self.account_id = account_id;
        return self;
    }

    pub fn execute(self: AccountBalanceQuery, client: *client_mod.Client) !AccountBalance {
        const account_id = self.account_id orelse return model.HelixError.InvalidId;
        const hbars = try client.getAccountBalance(account_id);
        return .{ .hbars = hbars };
    }
};

// Placeholder types - to be implemented
pub const AccountInfoQuery = struct {
    account_id: ?model.AccountId = null,

    pub fn setAccountId(self: *AccountInfoQuery, account_id: model.AccountId) *AccountInfoQuery {
        self.account_id = account_id;
        return self;
    }

    pub fn execute(self: AccountInfoQuery, client: *client_mod.Client) !model.AccountInfo {
        const account_id = self.account_id orelse return model.HelixError.InvalidId;
        return client.getAccountInfo(account_id);
    }
};

pub const AccountRecordsQuery = struct {
    account_id: ?model.AccountId = null,

    pub fn setAccountId(self: *AccountRecordsQuery, account_id: model.AccountId) *AccountRecordsQuery {
        self.account_id = account_id;
        return self;
    }

    pub fn execute(self: AccountRecordsQuery, client: *client_mod.Client) !model.AccountRecords {
        const account_id = self.account_id orelse return model.HelixError.InvalidId;
        return client.getAccountRecords(account_id);
    }
};

pub const TokenInfoQuery = struct {
    token_id: ?model.TokenId = null,

    pub fn setTokenId(self: *TokenInfoQuery, token_id: model.TokenId) *TokenInfoQuery {
        self.token_id = token_id;
        return self;
    }

    pub fn execute(self: TokenInfoQuery, client: *client_mod.Client) !model.TokenInfo {
        const token_id = self.token_id orelse return model.HelixError.InvalidId;
        return client.getTokenInfo(token_id);
    }
};

pub const TokenBalanceQuery = struct {
    account_id: ?model.AccountId = null,
    token_id: ?model.TokenId = null,

    pub fn setAccountId(self: *TokenBalanceQuery, account_id: model.AccountId) *TokenBalanceQuery {
        self.account_id = account_id;
        return self;
    }

    pub fn setTokenId(self: *TokenBalanceQuery, token_id: model.TokenId) *TokenBalanceQuery {
        self.token_id = token_id;
        return self;
    }

    pub fn execute(self: TokenBalanceQuery, client: *client_mod.Client) !model.TokenBalances {
        const account_id = self.account_id orelse return model.HelixError.InvalidId;
        return client.getTokenBalances(account_id);
    }
};

pub const ContractInfoQuery = struct {
    contract_id: ?model.ContractId = null,

    pub fn setContractId(self: *ContractInfoQuery, contract_id: model.ContractId) *ContractInfoQuery {
        self.contract_id = contract_id;
        return self;
    }

    pub fn execute(self: ContractInfoQuery, client: *client_mod.Client) !model.ContractInfo {
        const contract_id = self.contract_id orelse return model.HelixError.InvalidId;
        return client.getContractInfo(contract_id);
    }
};

pub const ContractCallQuery = struct {
    contract_id: ?model.ContractId = null,
    gas: u64 = 0,
    function_parameters: ?model.ContractFunctionParameters = null,
    sender_account_id: ?model.AccountId = null,

    pub fn setContractId(self: *ContractCallQuery, contract_id: model.ContractId) *ContractCallQuery {
        self.contract_id = contract_id;
        return self;
    }

    pub fn setGas(self: *ContractCallQuery, gas: u64) *ContractCallQuery {
        self.gas = gas;
        return self;
    }

    pub fn setFunctionParameters(self: *ContractCallQuery, params: model.ContractFunctionParameters) *ContractCallQuery {
        self.function_parameters = params;
        return self;
    }

    pub fn setSenderAccountId(self: *ContractCallQuery, account_id: model.AccountId) *ContractCallQuery {
        self.sender_account_id = account_id;
        return self;
    }

    pub fn execute(self: ContractCallQuery, client: *client_mod.Client) !model.ContractFunctionResult {
        const contract_id = self.contract_id orelse return model.HelixError.InvalidId;
        return client.contractCall(contract_id, self.gas, self.function_parameters, self.sender_account_id);
    }
};

pub const TransactionReceiptQuery = struct {};
