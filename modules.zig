const std = @import("std");
const Build = std.Build;
const Tuple = std.meta.Tuple;

const String = []const u8;

const ArrayList = std.ArrayList;
const ModuleBuilder = struct {
    const Self = @This();
    b: *Build,
    retry_list: ArrayList(Tuple(&.{ String, ArrayList(String) })),
    fn init(b: *Build) Self {
        return .{
            .b = b,
            .retry_list = ArrayList(Tuple(&.{ String, ArrayList(String) })).init(b.allocator),
        };
    }
    fn deinit(self: *Self) void {
        for (self.retry_list.items) |t| {
            t.@"1".deinit();
        }
    }

    fn resolveMissingDependencies(self: *Self) void {
        for (self.retry_list.items) |mod| {
            const mod_name = mod.@"0";
            const mod_depends = mod.@"1";
            var module = self.b.modules.get(mod_name).?;
            for (mod_depends.items) |dep| {
                module.dependencies.put(dep, self.b.modules.get(dep).?) catch @panic("OOM");
            }
        }
    }
};

pub fn buildModules(b: *Build, module_list: []const Tuple(&.{ []const u8, ?[]const String })) void {
    var mod_builder = ModuleBuilder.init(b);
    defer mod_builder.deinit();
    for (module_list) |mod| {
        var retry = ArrayList(String).init(b.allocator);
        const path = std.fmt.allocPrint(b.allocator, "src/{s}.zig", .{mod.@"0"}) catch @panic("OOM");
        var m = b.addModule(mod.@"0", .{ .source_file = .{ .path = path } });
        const deps = mod.@"1" orelse continue;
        for (deps) |dep| {
            if (b.modules.get(dep)) |d| {
                m.dependencies.put(dep, d) catch @panic("OOM");
            } else {
                retry.append(dep) catch @panic("OOM");
            }
        }
        if (retry.items.len > 0) {
            mod_builder.retry_list.append(.{ mod.@"0", retry }) catch @panic("OOM");
        }
    }

    mod_builder.resolveMissingDependencies();
}
