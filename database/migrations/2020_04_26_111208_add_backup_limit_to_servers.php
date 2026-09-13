<?php

use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Database\Migrations\Migration;

class AddBackupLimitToServers extends Migration
{
    /**
     * Run the migrations.
     */
    public function up(): void
    {
        $db = config('database.default');

        if ($db === 'sqlite') {
            $columns = DB::select("PRAGMA table_info('servers')");

            $hasBackupLimit = false;

            foreach ($columns as $column) {
                if ($column->name === 'backup_limit') {
                    $hasBackupLimit = true;
                    break;
                }
            }

            if ($hasBackupLimit) {
                return;
            }

            Schema::table('servers', function (Blueprint $table) {
                $table->unsignedInteger('backup_limit')->default(0);
            });

            return;
        }

        // MySQL / MariaDB
        $results = DB::select(
            'SELECT * FROM information_schema.COLUMNS
             WHERE TABLE_SCHEMA = ?
             AND TABLE_NAME = \'servers\'
             AND COLUMN_NAME = \'backup_limit\'',
            [
                config("database.connections.{$db}.database"),
            ]
        );

        if (count($results) === 1) {
            Schema::table('servers', function (Blueprint $table) {
                $table->unsignedInteger('backup_limit')
                    ->default(0)
                    ->change();
            });
        } else {
            Schema::table('servers', function (Blueprint $table) {
                $table->unsignedInteger('backup_limit')
                    ->default(0)
                    ->after('database_limit');
            });
        }
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::table('servers', function (Blueprint $table) {
            $table->dropColumn('backup_limit');
        });
    }
}