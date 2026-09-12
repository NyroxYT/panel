<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

class AddNullableFieldLastrun extends Migration
{
    /**
     * Run the migrations.
     */
    public function up()
    {
        if (DB::getDriverName() !== 'sqlite') {
            $table = DB::getQueryGrammar()->wrapTable('tasks');
            DB::statement('ALTER TABLE ' . $table . ' CHANGE `last_run` `last_run` TIMESTAMP NULL;');
            return;
        }

        // SQLite does not support MySQL's ALTER TABLE ... CHANGE syntax.
        // Rebuild the table while preserving its columns and data instead.
        $table = 'tasks';
        $oldTable = 'tasks_nxdactyl_old';
        $definition = DB::selectOne(
            "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = ?",
            [$table]
        );

        if (!$definition || empty($definition->sql)) {
            return;
        }

        $createSql = $definition->sql;
        $updatedSql = preg_replace(
            '/(`?last_run`?\\s+[^,\\)]+?)\\s+NOT\\s+NULL/i',
            '$1',
            $createSql,
            1
        );

        // If the column is already nullable, there is nothing to rebuild.
        if (!$updatedSql || $updatedSql === $createSql) {
            return;
        }

        $indexes = DB::select(
            "SELECT sql FROM sqlite_master WHERE type = 'index' AND tbl_name = ? AND sql IS NOT NULL",
            [$table]
        );

        DB::statement('PRAGMA foreign_keys = OFF');

        try {
            DB::statement('DROP TABLE IF EXISTS "' . $oldTable . '"');
            DB::statement('ALTER TABLE "' . $table . '" RENAME TO "' . $oldTable . '"');
            DB::statement($updatedSql);

            $columns = DB::select('PRAGMA table_info("' . $oldTable . '")');
            $columnNames = array_map(static fn ($column) => '"' . str_replace('"', '""', $column->name) . '"', $columns);
            $columnList = implode(', ', $columnNames);

            DB::statement(
                'INSERT INTO "' . $table . '" (' . $columnList . ') SELECT ' . $columnList . ' FROM "' . $oldTable . '"'
            );
            DB::statement('DROP TABLE "' . $oldTable . '"');

            foreach ($indexes as $index) {
                if (!empty($index->sql)) {
                    DB::statement($index->sql);
                }
            }
        } finally {
            DB::statement('PRAGMA foreign_keys = ON');
        }
    }

    /**
     * Reverse the migrations.
     */
    public function down()
    {
        if (DB::getDriverName() !== 'sqlite') {
            $table = DB::getQueryGrammar()->wrapTable('tasks');
            DB::statement('ALTER TABLE ' . $table . ' CHANGE `last_run` `last_run` TIMESTAMP;');
            return;
        }

        // SQLite cannot directly change a column back to NOT NULL. Keep the
        // nullable definition on SQLite; the historical rollback is retained
        // for MySQL-compatible installations above.
    }
}
