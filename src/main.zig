const std = @import("std");

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    const stderr = std.io.getStdErr().writer();
    var args_iter = std.process.args();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    var args = std.ArrayList([]const u8).init(allocator);
    defer args.deinit();

    var arg_count: usize = 0;
    while (args_iter.next()) |arg| {
        try args.append(arg);
        arg_count += 1;
    }

    if (arg_count < 4) {
        try stderr.print("Usage: combine <folder1> <folder2> ... -res <result_folder>\n", .{});
        return;
    }

    var result_folder: []const u8 = "";
    var folders = std.ArrayList([]const u8).init(allocator);
    defer folders.deinit();
    var found_res_flag = false;

    for (args.items[1..]) |arg| {
        if (found_res_flag) {
            result_folder = arg;
            found_res_flag = false;
        } else if (std.mem.eql(u8, arg, "-res")) {
            found_res_flag = true;
        } else {
            try folders.append(arg);
        }
    }

    if (result_folder.len == 0) {
        try stderr.print("Error: Result folder not specified.\n", .{});
        return;
    }

    // Create result directory if it doesn't exist
    try create_dir_if_not_exists(result_folder);

    var dest_dir = try std.fs.cwd().makeOpenPath(result_folder, .{});
    defer dest_dir.close();

    for (folders.items) |folder| {
        // Convert relative path to absolute path
        const abs_folder = try std.fs.cwd().realpathAlloc(allocator, folder);
        defer allocator.free(abs_folder);

        var src_dir = try std.fs.openDirAbsolute(abs_folder, .{
            .access_sub_paths = false,
            .iterate = true,
            .no_follow = true,
        });
        defer src_dir.close();

        var walker = try src_dir.walk(allocator);
        defer walker.deinit();

        while (try walker.next()) |entry| {
            const dest_path = try std.fs.path.join(allocator, &.{ result_folder, entry.path });
            defer allocator.free(dest_path);

            switch (entry.kind) {
                .file => {
                    const source_path = try std.fs.path.join(allocator, &.{ folder, entry.path });
                    defer allocator.free(source_path);

                    // Create parent directory if it doesn't exist
                    const dest_parent = std.fs.path.dirname(dest_path) orelse ".";
                    try std.fs.cwd().makePath(dest_parent);

                    // Copy the file using Dir.copyFile
                    try entry.dir.copyFile(entry.basename, dest_dir, entry.path, .{});
                    try stdout.print("Copied {s}\n", .{entry.path});
                },
                .directory => {
                    dest_dir.makePath(entry.path) catch |err| {
                        if (err != error.PathAlreadyExists) return err;
                    };
                },
                else => continue,
            }
        }

        deleteDirectory(folder) catch |err| {
            try stderr.print("Error deleting directory {s}: {}\n", .{ folder, err });
        };
    }
}

fn deleteDirectory(folder: []const u8) !void {
    try std.fs.cwd().deleteTree(folder);
}

fn create_dir_if_not_exists(path: []const u8) !void {
    std.fs.cwd().makeDir(path) catch |err| {
        if (err != error.PathAlreadyExists) {
            return err;
        }
        // If directory already exists, that's fine
    };
}
