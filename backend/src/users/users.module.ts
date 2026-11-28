import { Module } from '@nestjs/common';
import { DatabaseModule } from '../database/database.module';
import { AdminController, PlatformAdminGuard } from './admin.controller';

@Module({
  imports: [DatabaseModule],
  controllers: [AdminController],
  providers: [PlatformAdminGuard],
})
export class UsersModule {}
