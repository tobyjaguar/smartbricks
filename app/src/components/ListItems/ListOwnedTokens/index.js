/**
This application is for use with SmartPiggies.

SmartPiggies is an open source standard for
a free peer to peer global derivatives market.

Copyright (C) 2019, Arief, Algya, Lee

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.
**/
import React, { Component } from 'react'
import { drizzleConnect } from 'drizzle-react'
import PropTypes from 'prop-types'

import Table from '@material-ui/core/Table';
import TableBody from '@material-ui/core/TableBody';
import TableCell from '@material-ui/core/TableCell';
import TableRow from '@material-ui/core/TableRow';

class ListOwnedTokens extends Component {
  constructor(props, context) {
    super(props)

    this.contracts = context.drizzle.contracts

  }

  render() {
    return (
      <div>
      <Table>
        <TableBody>
          <TableRow>
            <TableCell align="left">
              {this.props.index+1}
            </TableCell>
            <TableCell align="right">
              tokenId: {this.props.item.toString()}
            </TableCell>
          </TableRow>
        </TableBody>
      </Table>
      </div>
    )
  }
}

ListOwnedTokens.contextTypes = {
  drizzle: PropTypes.object
}

export default drizzleConnect(ListOwnedTokens)
