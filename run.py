import asyncio
import datetime
import random
import traceback

import dataset
import discord
from discord import Colour, Embed, Game
from discord.ext import commands
from stuf import stuf

from src.util import CONFIG, create_logger


# Set up Logging
logger = create_logger('discord')
guild_db = dataset.connect(f"sqlite:///{CONFIG['database']['guild_db_path']}", row_type=stuf)

prefix_table = guild_db['prefixes']


def get_prefix(bot, msg):
    # Works without prefix in DM's
    if isinstance(msg.channel, discord.abc.PrivateChannel):
        return commands.when_mentioned_or(*CONFIG['discord']['prefixes'], '')(bot, msg)

    # Check for custom per-guild prefix
    entry = prefix_table.find_one(guild_id=msg.guild.id)
    if entry is not None:
        return commands.when_mentioned_or(entry.prefix)(bot, msg)
    return commands.when_mentioned_or(*CONFIG['discord']['prefixes'])(bot, msg)


class Bot(commands.AutoShardedBot):
    def __init__(self):
        super().__init__(
            command_prefix=get_prefix,
            description=CONFIG['discord']['description'],
            pm_help=None,
            game=Game(name=random.choice(CONFIG['discord']['playing_states']))
        )
        self.start_time = datetime.datetime.now()
        self.owner = None
        self.voice_client = None
        self.error_channel = None
        self.guild_channel = None

    # Helper function to create and return an Embed with red colour.
    @staticmethod
    def make_error_embed(description):
        return Embed(colour=Colour.red(), description=description)

    async def on_command_error(self, ctx: commands.Context, error: commands.CommandError):
        if isinstance(error, commands.BadArgument):
            await ctx.send(embed=self.make_error_embed(f'**You invoked the Command with the wrong type of arguments.'
                                                       f' Use `!help command` to get information about its usage.**\n'
                                                       f'({error})'))
        elif isinstance(error, commands.CommandNotFound):
            pass
        elif isinstance(error, commands.CommandInvokeError):
            # Check if it was "Forbidden" (no direct messages), notify and exit early
            if isinstance(error.original, discord.errors.Forbidden):
                return await ctx.send(embed=discord.Embed(
                    title='<:sadpanda:319417001485533188> You have Direct Messages disabled.',
                    description=(f'The Command you invoked requires me to send you a *Direct Message*. This is often '
                                 f'necessary to ensure that other people do not receive information that is intended '
                                 f'for you, or to prevent spam. Please disable this by doing the following:\n'
                                 f'- Right click on this Server and choose **Privacy Settings**\n'
                                 f'- Tick **Allow direct messages from server members**.\n'
                                 f'That\'s all, thank you!'),
                    colour=discord.Colour.blue()
                ))

            await ctx.send(embed=self.make_error_embed(
                (f'**An Error occurred through the invocation of the command**.\n'
                 f'Please contact Volcyy#2359 with a detailed '
                 f'description of the problem and how it was created. Thanks!')
            ))
            # print('In {0.command.qualified_name}:'.format(ctx), file=sys.stderr)
            # traceback.print_tb(error.original.__traceback__)
            # print('{0.__class__.__name__}: {0}'.format(error.original), file=sys.stderr)
            readable_tb = '```py\n' \
                         + '\n'.join(traceback.format_list(traceback.extract_tb(error.original.__traceback__))) \
                         + f'```\n```py\n{error.original}```'

            await self.error_channel.send(embed=discord.Embed(
                title=f'Exception occurred in Command `{ctx.command.qualified_name}`:',
                colour=discord.Colour.red(),
                timestamp=datetime.datetime.now()
            ).add_field(
                name='Invocation',
                value=(f'**By**: {ctx.author} ({ctx.author.id})\n'
                       f'**Channel**: {f"{ctx.channel.name} ({ctx.channel.id})" if ctx.channel is not None else "DM"}\n'
                       f'**Guild**: {f"{ctx.guild.name} ({ctx.guild.id})" if ctx.guild is not None else "DM"}\n'
                       f'**Message**: {ctx.message.content}')
            ).add_field(
                name='Traceback',
                value=readable_tb if len(readable_tb) < 1024 else f'Too long to display, original:\n`{error.original}`'
            ))
        elif isinstance(error, commands.CommandOnCooldown):
            await ctx.send(embed=self.make_error_embed('This Command is currently on cooldown.'))
        elif isinstance(error, commands.DisabledCommand):
            await ctx.send(embed=self.make_error_embed('Sorry, this Command is currently disabled for maintenance.'))
        elif isinstance(error, commands.NoPrivateMessage):
            await ctx.send(embed=self.make_error_embed('This Command cannot be used in private Messages.'))
        else:
            pass

    async def on_ready(self):
        print('= LOGGED IN =')
        print(f'User: {self.user}')
        print(f'ID: {self.user.id}')
        print(f'Connected to {len(self.guilds)} Guilds.')
        print(f'Connected to {len(self.users)} Users.')
        print(f'Total of {len(self.commands)} Commands in {len(self.cogs)} Cogs.')
        print(f'Invite Link:\nhttps://discordapp.com/oauth2/authorize?&client_id={self.user.id}&scope=bot')
        print('=============')
        self.owner = self.get_user(self.owner_id)
        self.error_channel = self.get_channel(CONFIG['discord']['error_channel_id'])
        self.guild_channel = self.get_channel(CONFIG['discord']['guild_channel_id'])

    async def on_message(self, msg):
        if msg.author.bot:
            return

        # await msg.channel.trigger_typing()
        await self.process_commands(msg)

    @staticmethod
    async def _guild_event_note(destination: discord.abc.Messageable, guild: discord.Guild, title: str):
        note = discord.Embed()
        note.set_thumbnail(url=guild.icon_url)
        note.title = title
        online_members = sum(1 for m in guild.members if m.status != discord.Status.online)
        note.add_field(name='Members', value=f'Total: {guild.member_count}\nOnline: {online_members}')
        note.add_field(name='Channels', value=str(sum(1 for _ in guild.channels)))
        note.add_field(name='Owner', value=f'{guild.owner.name}#{guild.owner.discriminator}\nID: `{guild.owner_id}`')
        await destination.send(embed=note)

    async def on_guild_join(self, guild: discord.Guild):
        await self._guild_event_note(self.guild_channel, guild, f'Joined Guild {guild.name} ({guild.id})')

    async def on_guild_remove(self, guild: discord.Guild):
        await self._guild_event_note(self.guild_channel, guild, f'Left Guild {guild.name} ({guild.id})')

client = Bot()


# Base path where cogs house
COGS_BASE_PATH = 'src.cogs.'

# Cogs to load on login
COGS_ON_LOGIN = [
    'admin',
    'meta',
    'mod',
    'streams',
    'roles'
]


if __name__ == '__main__':
    print('Loading Cogs...')
    for cog in COGS_ON_LOGIN:
        try:
            client.load_extension(COGS_BASE_PATH + cog)
        except ModuleNotFoundError as err:
            print(f'Could not load Cog \'{cog}\': {err}.')

    print('Logging in...')
    client.run(CONFIG['discord']['token'])
    client.close()
    print('Logged off.')


