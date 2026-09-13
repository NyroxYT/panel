<?php

use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Database\Migrations\Migration;

class CreateBackupsTable extends Migration
{
    /**
     * Run the migrations.
     */
    public function up(): void
    {
        $db = config('database.default');

        // SQLite does not have information_schema.
        // Use sqlite_master to find old backup plugin tables.
        if ($db === 'sqlite') {
            $results = DB::select(
                "SELECT name
                 FROM sqlite_master
                 WHERE type = 'table'
                 AND name LIKE 'backup%'
                 AND name NOT LIKE '%_plugin_bak'"
            );

            foreach ($results as $result) {
                $tableName = $result->name;

                // Do not rename the table we're about to create.
                if ($tableName !== 'backups') {
                    Schema::rename(
                        $tableName,
                        $tableName . '_plugin_bak'
                    );
                }
            }
        } else {
            // MySQL / MariaDB
            $results = DB::select(
                'SELECT TABLE_NAME
                 FROM information_schema.tables
                 WHERE table_schema = ?
                 AND table_name LIKE ?
                 AND table_name NOT LIKE \'%_plugin_bak\'',
                [
                    config("database.connections.{$db}.database"),
                    'backup%',
                ]
            );

            foreach ($results as $result) {
                Schema::rename(
                    $result->TABLE_NAME,
                    $result->TABLE_NAME . '_plugin_bak'
                );
            }
        }

        Schema::create('backups', function (Blueprint $table) {
            $table->bigIncrements('id');
            $table->unsignedInteger('server_id');
            $table->char('uuid', 36);
            $table->string('name');
            $table->text('ignored_files');
            $table->string('disk');
            $table->string('sha256_hash')->nullable();
            $table->integer('bytes')->default(0);
            $table->timestamp('completed_at')->nullable();
            $table->timestamps();
            $table->softDeletes();

            $table->unique('uuid');
            $table->foreign('server_id')
                ->references('id')
                ->on('servers')
                ->onDelete('cascade');
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::dropIfExists('backups');
    }
}