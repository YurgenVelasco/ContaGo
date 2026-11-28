import { Module } from '@nestjs/common';
import { DatabaseModule } from '../database/database.module';
import { BusinessAccess, BusinessGuard } from './business-access';
import { BusinessesController } from './businesses.controller';

@Module({
  imports: [DatabaseModule],
  providers: [BusinessAccess, BusinessGuard],
  controllers: [BusinessesController],
  exports: [BusinessAccess, BusinessGuard],
})
export class BusinessesModule {}
