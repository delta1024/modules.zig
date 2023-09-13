const std = @import("std");
const Build = std.Build;
const Tuple = std.meta.Tuple;

const String = []const u8;

pub const ProgramModule = struct {
    name: String,
    public: bool = false,
    dependencies: ?[]const String = null,
};

fn createModulePath(a: std.mem.Allocator, parent_name: String) String {
    return std.fmt.allocPrint(a, "src/{s}.zig", .{parent_name}) catch @panic("OOM");
}

const ArrayList = std.ArrayList;
const ModuleBuilder = struct {
    const Self = @This();
    modules: std.StringHashMap(*Build.Module),
    b: *Build,
    retry_list: ArrayList(Tuple(&.{ String, ArrayList(String) })),
    fn init(b: *Build) Self {
        return .{
            .b = b,
            .retry_list = ArrayList(Tuple(&.{ String, ArrayList(String) })).init(b.allocator),
            .modules = std.StringHashMap(*Build.Module).init(b.allocator),
        };
    }
    fn deinit(self: *Self) void {
        for (self.retry_list.items) |t| {
            t.@"1".deinit();
        }
        self.retry_list.deinit();
        self.modules.deinit();
    }

    fn resolveMissingDependencies(self: *Self) void {
        for (self.retry_list.items) |mod| {
            const mod_name = mod.@"0";
            const mod_depends = mod.@"1";
            var module = self.b.modules.get(mod_name) orelse self.modules.get(mod_name).?;
            for (mod_depends.items) |dep| {
                module.dependencies.put(dep, self.b.modules.get(dep).?) catch @panic("OOM");
            }
        }
    }
    fn addModule(self: *ModuleBuilder, name: []const u8, op: Build.CreateModuleOptions) *Build.Module {
        var n = self.b.createModule(op);
        self.modules.put(name, n) catch @panic("OOM");
        return n;
    }
};

pub fn buildModules(b: *Build, module_list: []const ProgramModule) void {
    var mod_builder = ModuleBuilder.init(b);
    defer mod_builder.deinit();
    for (module_list) |mod| {
        var retry = ArrayList(String).init(b.allocator);
        const path = createModulePath(b.allocator, mod.name);
        var m = if (mod.public) bk: {
            break :bk b.addModule(mod.name, .{ .source_file = .{ .path = path } });
        } else mod_builder.addModule(mod.name, .{ .source_file = .{ .path = path } });
        const deps = mod.dependencies orelse continue;

        for (deps) |dep| {
            if (b.modules.get(dep)) |d| {
                m.dependencies.put(dep, d) catch @panic("OOM");
            } else if (mod_builder.modules.get(dep)) |d| {
                m.dependencies.put(dep, d) catch @panic("OOM");
            } else {
                retry.append(dep) catch @panic("OOM");
            }
        }
        if (retry.items.len > 0) {
            mod_builder.retry_list.append(.{ mod.name, retry }) catch @panic("OOM");
        }
    }

    mod_builder.resolveMissingDependencies();
}
