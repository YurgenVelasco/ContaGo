import { Module } from '@nestjs/common';
import { BusinessesModule } from '../businesses/businesses.module';
import { DatabaseModule } from '../database/database.module';
import { MembershipsController } from './memberships.controller';

@Module({
  imports: [BusinessesModule, DatabaseModule],
  controllers: [MembershipsController],
})
export class MembershipsModule {}
