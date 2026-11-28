import { Module } from '@nestjs/common';
import { AuthModule } from './auth/auth.module';
import { BusinessesModule } from './businesses/businesses.module';
import { ConfigModule } from './config/config.module';
import { HealthModule } from './health/health.module';
import { MembershipsModule } from './memberships/memberships.module';
import { UsersModule } from './users/users.module';

@Module({
  imports: [ConfigModule, HealthModule, AuthModule, UsersModule, BusinessesModule, MembershipsModule],
})
export class AppModule {}
