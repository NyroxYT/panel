<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

return new class extends Migration
{
    public function up(): void
    {
        if (DB::getDriverName() !== 'sqlite') {
            return;
        }

        DB::statement('PRAGMA foreign_keys=OFF');

        DB::statement('
            CREATE TABLE users_new (
                id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
                uuid VARCHAR NOT NULL,
                email VARCHAR NOT NULL,
                password TEXT NOT NULL,
                remember_token VARCHAR NULL,
                language VARCHAR NOT NULL DEFAULT \'en\',
                root_admin INTEGER NOT NULL DEFAULT \'0\',
                use_totp INTEGER NOT NULL,
                totp_secret TEXT NULL,
                created_at DATETIME NULL,
                updated_at DATETIME NULL,
                name_first VARCHAR NULL,
                name_last VARCHAR NULL,
                username VARCHAR NOT NULL,
                gravatar TINYINT(1) NOT NULL DEFAULT \'1\',
                external_id VARCHAR NULL,
                totp_authenticated_at DATETIME NULL
            )
        ');

        DB::statement('
            INSERT INTO users_new
            SELECT
                id,
                uuid,
                email,
                password,
                remember_token,
                language,
                root_admin,
                use_totp,
                totp_secret,
                created_at,
                updated_at,
                name_first,
                name_last,
                username,
                gravatar,
                external_id,
                totp_authenticated_at
            FROM users
        ');

        DB::statement('DROP TABLE users');
        DB::statement('ALTER TABLE users_new RENAME TO users');

        DB::statement('PRAGMA foreign_keys=ON');
    }

    public function down(): void
    {
        // Keep external_id nullable for SQLite.
    }
};